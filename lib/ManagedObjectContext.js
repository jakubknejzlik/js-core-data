const ManagedObject = require("./ManagedObject");
const ManagedObjectID = require("./ManagedObjectID");
const FetchRequest = require("./FetchRequest");
const Predicate = require("./FetchClasses/Predicate");
const SortDescriptor = require("./FetchClasses/SortDescriptor");
const RelationshipDescription = require("./Descriptors/RelationshipDescription");
const async = require("async");
const ac = require("array-control");
const Lock = require("lock");
const Promise = require("bluebird");

class ManagedObjectContext extends Object {
  constructor(storeCoordinator) {
    super();
    this.locals = {};
    this.storeCoordinator = storeCoordinator;
    this.insertedObjects = [];
    this.updatedObjects = [];
    this.deletedObjects = [];
    this.registeredObjects = [];
    this.locked = false;
    this.saving = false;
    this.lock = new Lock();
    this.destroyed = false;
  }

  hasChanges() {
    return (
      this.insertedObjects.length > 0 ||
      this.updatedObjects.length > 0 ||
      this.deletedObjects.length > 0
    );
  }

  insertObject(object) {
    if (this.locked) {
      throw new Error("context is locked");
    }
    if (object.managedObjectContext !== this) {
      throw new Error("cannot insert object to another context");
    }
    if (this.insertedObjects.indexOf(object) < 0) {
      object._isFault = false;
      let values = {};
      for (let attributeDescription of object.entity.attributes) {
        let defaultValue = attributeDescription.defaultValue();
        if (defaultValue !== null && !attributeDescription.isTransient()) {
          values[attributeDescription.name] = defaultValue;
        }
      }
      object._data = {};
      object.setValues(values, {
        privates: true
      });
      object._isInserted = true;
      object._isDeleted = false;
      object._objectID = this.storeCoordinator.temporaryObjectID(object);
      ac.addObject(this.insertedObjects, object);
      ac.addObject(this.registeredObjects, object);
      object.awakeFromInsert();
    }
    return ac.removeObject(this.deletedObjects, object);
  }

  deleteObject(object) {
    if (this.locked) {
      throw new Error("context is locked");
    }
    return this._deleteObjectWithoutLockCheck(object);
  }

  _deleteObjectWithoutLockCheck(object) {
    if (object.managedObjectContext !== this) {
      throw new Error("cannot delete object from another context");
    }
    ac.removeObject(this.insertedObjects, object);
    object._isDeleted = true;
    return ac.addObject(this.deletedObjects, object);
  }

  createObjectWithName(entityName) {
    return this.storeCoordinator.objectModel.insertObjectIntoContext(
      entityName,
      this
    );
  }

  create(entityName, data, allowedAttributes) {
    var object;
    object = this.createObjectWithName(entityName);
    object.setValues(data, allowedAttributes);
    if (data && data.id) {
      object.id = data.id;
    }
    return object;
  }

  getObjectWithId(entityName, id, callback) {
    return new Promise((resolve, reject) => {
      return async.nextTick(() => {
        let entity = this.storeCoordinator.objectModel.getEntity(entityName);
        if (!entity) {
          return reject(new Error("entity " + entityName + " not found"));
        }
        return this.getObjectWithObjectID(new ManagedObjectID(id, entity))
          .then(resolve)
          ["catch"](reject);
      });
    }).asCallback(callback);
  }

  getObjectWithObjectID(ObjectID, callback) {
    return new Promise(
      (function(_this) {
        return function(resolve, reject) {
          var request;
          request = new FetchRequest(ObjectID.entity);
          request.setLimit(1);
          request.predicate = new Predicate(ObjectID);
          return _this.storeCoordinator.execute(request, _this, function(
            err,
            objects
          ) {
            if (err) {
              return reject(err);
            }
            if (objects[0]) {
              ac.addObject(_this.registeredObjects, objects[0]);
              return resolve(objects[0]);
            } else {
              return resolve(null);
            }
          });
        };
      })(this)
    ).asCallback(callback);
  }

  getObjects(entityName, options, callback) {
    if (typeof options === "function") {
      callback = options;
      options = void 0;
    }
    return new Promise(
      (function(_this) {
        return function(resolve, reject) {
          return _this.storeCoordinator.execute(
            _this._getFetchRequest(entityName, options),
            _this,
            function(err, objects) {
              if (err) {
                return reject(err);
              } else {
                ac.addObjects(_this.registeredObjects, objects);
                return resolve(objects);
              }
            }
          );
        };
      })(this)
    ).asCallback(callback);
  }

  fetch(entityName, options, callback) {
    if (typeof options === "function") {
      callback = options;
      options = void 0;
    }
    return new Promise(
      (function(_this) {
        return function(resolve, reject) {
          var request;
          request = _this._getFetchRequest(entityName, options);
          request.resultType = FetchRequest.RESULT_TYPE.VALUES;
          return _this.storeCoordinator.execute(request, _this, function(
            err,
            values
          ) {
            if (err) {
              return reject(err);
            } else {
              return resolve(values);
            }
          });
        };
      })(this)
    ).asCallback(callback);
  }

  _getFetchRequest(entityName, options) {
    var ascending,
      having,
      havingPredicate,
      i,
      len,
      predicate,
      request,
      sort,
      sortDescriptors,
      sortItem,
      where;
    options = options || {};
    predicate = null;
    havingPredicate = null;
    sortDescriptors = [];
    if (typeof options.where === "string") {
      predicate = new Predicate(options.where);
    } else if (Array.isArray(options.where)) {
      where = options.where.slice();
      where.unshift(null);
      predicate = new (Function.prototype.bind.apply(Predicate, where))();
    } else if (typeof options.where === "object") {
      predicate = new Predicate(options.where);
    }
    if (typeof options.having === "string") {
      havingPredicate = new Predicate(options.having);
    } else if (Array.isArray(options.having)) {
      having = options.having.slice();
      having.unshift(null);
      havingPredicate = new (Function.prototype.bind.apply(
        Predicate,
        having
      ))();
    } else if (typeof options.having === "object") {
      havingPredicate = new Predicate(options.having);
    }
    sort = options.sort || options.order;
    if (typeof sort === "string") {
      sort = [sort];
    }
    if (Array.isArray(sort)) {
      for (i = 0, len = sort.length; i < len; i++) {
        sortItem = sort[i];
        ascending = true;
        if (sortItem[0] === "-") {
          ascending = false;
          sortItem = sortItem.substring(1);
        }
        sortDescriptors.push(new SortDescriptor(sortItem, ascending));
      }
    }
    request = new FetchRequest(
      this.storeCoordinator.objectModel.getEntity(entityName),
      predicate,
      sortDescriptors
    );
    request.predicate = predicate;
    request.havingPredicate = havingPredicate;
    request.sortDescriptors = sortDescriptors;
    if (options.offset && !options.limit) {
      throw new Error("limit must be supplied when fetching with offset");
    }
    if (options.limit) {
      request.setLimit(options.limit);
    }
    if (options.offset) {
      request.setOffset(options.offset);
    }
    request.fields = options.fields;
    request.group = options.group;
    return request;
  }

  getObject(entityName, options, callback) {
    if (typeof options === "function") {
      callback = options;
      options = null;
    }
    return new Promise(
      (function(_this) {
        return function(resolve, reject) {
          options = options || {};
          options.limit = 1;
          return _this
            .getObjects(entityName, options)
            .then(function(objects) {
              if (objects.length > 0) {
                return resolve(objects[0]);
              } else {
                return resolve(null);
              }
            })
            ["catch"](reject);
        };
      })(this)
    ).asCallback(callback);
  }

  getOrCreateObject(entityName, options, defaultValues, callback) {
    if (typeof defaultValues === "function") {
      callback = defaultValues;
      defaultValues = void 0;
    }
    return new Promise(
      (function(_this) {
        return function(resolve, reject) {
          return _this.lock(entityName, function(release) {
            return _this.getObject(entityName, options, function(err, object) {
              if (err) {
                release()();
                return reject(err);
              }
              if (!object) {
                object = _this.create(entityName, defaultValues);
              }
              resolve(object);
              return release()();
            });
          });
        };
      })(this)
    ).asCallback(callback);
  }

  getObjectsCount(entityName, options, callback) {
    if (typeof options === "function") {
      callback = options;
      options = void 0;
    }
    return new Promise(
      (function(_this) {
        return function(resolve, reject) {
          return _this.storeCoordinator.numberOfObjectsForFetchRequest(
            _this._getFetchRequest(entityName, options),
            function(err, count) {
              if (err) {
                return reject(err);
              } else {
                return resolve(count);
              }
            }
          );
        };
      })(this)
    ).asCallback(callback);
  }

  _getObjectsForRelationship(relationship, object, context, callback) {
    if (object.objectID.isTemporaryID) {
      return callback(null, []);
    }
    return this.storeCoordinator._valuesForForRelationship(
      relationship,
      object.objectID,
      context,
      (function(_this) {
        return function(err, objects) {
          if (err) {
            return callback(err);
          }
          ac.addObjects(_this.registeredObjects, objects);
          return callback(null, objects);
        };
      })(this)
    );
  }

  saveAndDestroy(callback) {
    let promise = this.save().then(
      (function(_this) {
        return function() {
          _this.destroy();
          if (callback) {
            return callback();
          }
        };
      })(this)
    );
    if (callback) {
      return promise["catch"](callback);
    }
    return promise;
  }

  async save(callback) {
    return Promise.resolve(this._save()).asCallback(callback);
  }
  async _save(callback) {
    if (this.locked) {
      throw new Error("context is locked");
    }
    if (this.saving) {
      throw new Error("context is already saving");
    }
    this.saving = true;

    var allObjects = [];
    let changedObjects = this.insertedObjects.concat(
      this.updatedObjects,
      this.deletedObjects
    );
    for (let obj of changedObjects) {
      if (allObjects.indexOf(obj) < 0) {
        allObjects.push(obj);
      }
    }
    await Promise.all(allObjects.map(obj => obj.willSave()));

    if (!this.hasChanges) {
      this.saving = false;
      return;
    } else {
      this.locked = true;
    }
    try {
      await this._processDeletedObjects();
      await this._saveInStoreCoordinator();

      for (let object of this.insertedObjects) {
        object._changes = null;
        object._relationChanges = null;
        object._isInserted = false;
      }
      for (let object of this.updatedObjects) {
        object._changes = null;
        object._relationChanges = null;
        object._isUpdated = false;
      }
      for (let object of this.deletedObjects) {
        object._isDeleted = false;
      }
      this.insertedObjects = [];
      this.updatedObjects = [];
      this.deletedObjects = [];
      this.locked = false;

      await Promise.all(allObjects.map(obj => obj.didSave()));
      this.locked = false;
    } catch (err) {
      throw err;
    } finally {
      this.locked = false;
      this.saving = false;
    }
  }

  async _saveInStoreCoordinator() {
    return new Promise((resolve, reject) => {
      return this.storeCoordinator.saveContext(this, err => {
        if (err) return reject(err);
        resolve();
      });
    });
  }

  reset() {
    if (this.locked) {
      throw new Error("context is locked");
    }
    this.registeredObjects = [];
    this.updatedObjects = [];
    return (this.deletedObjects = []);
  }

  destroy() {
    if (this.destroyed) {
      throw new Error("destroying already destroyed context");
    }
    if (this.locked) {
      throw new Error("context is locked");
    }
    this.destroyed = true;
    delete this.registeredObjects;
    delete this.insertedObjects;
    delete this.updatedObjects;
    delete this.deletedObjects;
    return delete this.storeCoordinator;
  }

  async _processDeletedObjects() {
    for (let obj of this.deletedObjects) {
      await obj.prepareForDeletion();
    }
  }

  _didUpdateObject(object) {
    if (this.destroyed) {
      throw new Error("updating values on object on destroyed context");
    }
    if (this.locked) {
      throw new Error("cannot update object when it's context is locked");
    }
    if (this.updatedObjects.indexOf(object) < 0) {
      return ac.addObject(this.updatedObjects, object);
    }
  }
}

Object.defineProperties(ManagedObjectContext.prototype, {
  hasChanges: {
    get: ManagedObjectContext.prototype.hasChanges
  }
});

module.exports = ManagedObjectContext;
