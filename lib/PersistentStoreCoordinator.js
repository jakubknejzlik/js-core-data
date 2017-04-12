var FetchRequest, IncrementalStore, ManagedObject, PersistentStoreCoordinator, PersistentStoreRequest, Predicate, _knownStoreProtocols, ac, async, url,
  extend = function(child, parent) { for (var key in parent) { if (hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
  hasProp = {}.hasOwnProperty;

PersistentStoreRequest = require('./stores/PersistentStoreRequest');

IncrementalStore = require('./stores/IncrementalStore');

ManagedObject = require('./ManagedObject');

Predicate = require('./FetchClasses/Predicate');

FetchRequest = require('./FetchRequest');

async = require('async');

url = require('url');

ac = require('array-control');

_knownStoreProtocols = {
  'sqlite:': 'SQLiteStore',
  'mysql:': 'MySQLStore',
  'postgres:': 'PostgreSQLStore'
};

PersistentStoreCoordinator = (function(superClass) {
  var registeredStoreTypes;

  extend(PersistentStoreCoordinator, superClass);

  PersistentStoreCoordinator.STORE_TYPE_MYSQL = 'MySQLStore';

  PersistentStoreCoordinator.STORE_TYPE_SQLITE = 'SQLiteStore';

  PersistentStoreCoordinator.STORE_TYPE_POSTGRES = 'PostgreSQLStore';

  registeredStoreTypes = {};

  function PersistentStoreCoordinator(objectModel, globals) {
    this.objectModel = objectModel;
    this.globals = globals != null ? globals : {};
    if (!this.objectModel) {
      throw new Error('Cannot create coordinator without object model');
    }
    this.persistentStores = [];
    this.waitingRequests = [];
    this.temporaryId = 1;
    this.parallelExecution = true;
  }

  PersistentStoreCoordinator.registerStoreClass = function(storeClass, storeType) {
    registeredStoreTypes[storeType] = storeClass;
    return this;
  };

  PersistentStoreCoordinator.prototype.addStore = function(storeTypeOrStore, URL, callback) {
    var parsedURL, store, storeClass;
    store = null;
    if (storeTypeOrStore instanceof IncrementalStore) {
      store = storeTypeOrStore;
    } else {
      if (URL === void 0) {
        URL = storeTypeOrStore;
        parsedURL = url.parse(URL);
        storeTypeOrStore = _knownStoreProtocols[parsedURL.protocol];
      }
      if (!storeTypeOrStore) {
        throw new Error('unknown store for url ' + URL);
      }
      storeClass = registeredStoreTypes[storeTypeOrStore];
      if (!storeClass) {
        storeClass = require('./stores/Defaults/' + storeTypeOrStore);
      }
      store = new storeClass(this, URL, this.globals);
    }
    if (!store) {
      throw new Error('could not identify store');
    }
    if (callback) {
      console.error('adding store with callback is deprecated');
      return store.syncSchema((function(_this) {
        return function(err) {
          if (!err) {
            _this.persistentStores.push(store);
          }
          if (callback) {
            return callback(err);
          }
        };
      })(this));
    } else {
      return this.persistentStores.push(store);
    }
  };

  PersistentStoreCoordinator.prototype.execute = function(request, context, callback) {
    this.waitingRequests.push({
      request: request,
      context: context,
      callback: callback
    });
    return this._executeNextRequestIfPossible();
  };

  PersistentStoreCoordinator.prototype._executeNextRequestIfPossible = function() {
    var callback, context, info, obj, ref, request, store;
    if (this.executingRequest && !this.parallelExecution) {
      return;
    }
    info = this.waitingRequests.shift();
    if (!info) {
      return;
    }
    this.executingRequest = true;
    request = info.request;
    context = info.context;
    callback = info.callback;
    if (request.type === 'fetch' && ((ref = request.predicate) != null ? ref.isObjectIDPredicate() : void 0)) {
      obj = this._objectFromContextCache(context, request.predicate.objectID());
      if (obj) {
        return this._requestCompleted(callback, null, [obj]);
      }
    }
    store = this.persistentStores[0];
    return store.execute(request, context, (function(_this) {
      return function(err, ObjectIDsOrValues, objectValues) {
        var j, len, objectID, objects;
        if (objectValues == null) {
          objectValues = {};
        }
        if (err) {
          return _this._requestCompleted(callback, err);
        }
        if (request.resultType === FetchRequest.RESULT_TYPE.VALUES) {
          return callback(null, ObjectIDsOrValues);
        }
        objects = [];
        for (j = 0, len = ObjectIDsOrValues.length; j < len; j++) {
          objectID = ObjectIDsOrValues[j];
          obj = _this._objectFromContextCache(context, objectID);
          if (obj) {
            objects.push(obj);
          } else {
            objects.push(_this._objectForID(request.entity, context, objectID, objectValues[objectID.toString()]));
          }
        }
        return _this._requestCompleted(callback, null, objects);
      };
    })(this));
  };

  PersistentStoreCoordinator.prototype.numberOfObjectsForFetchRequest = function(request, callback) {
    var store;
    store = this.persistentStores[0];
    return store.numberOfObjectsForFetchRequest(request, callback);
  };

  PersistentStoreCoordinator.prototype._requestCompleted = function(callback, err, objects) {
    this.executingRequest = false;
    callback(err, objects);
    return this._executeNextRequestIfPossible();
  };

  PersistentStoreCoordinator.prototype._objectForID = function(entity, context, objectID, objectValues) {
    var object, subclass;
    if (objectValues == null) {
      objectValues = {};
    }
    subclass = this.objectModel.subclassForEntity(entity.name);
    object = new subclass(entity, context, objectValues);
    object._objectID = objectID;
    object.awakeFromFetch();
    return object;
  };

  PersistentStoreCoordinator.prototype._objectFromContextCache = function(context, objectID) {
    var j, len, object, ref;
    if (!context.registeredObjects) {
      return null;
    }
    ref = context.registeredObjects;
    for (j = 0, len = ref.length; j < len; j++) {
      object = ref[j];
      if (object.objectID.isEqual(objectID)) {
        return object;
      }
    }
    return null;
  };

  PersistentStoreCoordinator.prototype.saveContext = function(context, callback) {
    var j, len, obj, ref, request, temporaryObjectIDs;
    request = new PersistentStoreRequest('save');
    request.insertedObjects = context.insertedObjects;
    request.updatedObjects = [];
    ref = context.updatedObjects;
    for (j = 0, len = ref.length; j < len; j++) {
      obj = ref[j];
      if (!ac.hasObject(request.insertedObjects, obj)) {
        request.updatedObjects.push(obj);
      }
    }
    request.deletedObjects = context.deletedObjects;
    temporaryObjectIDs = [];
    return async.forEach(this.persistentStores, function(store, cb) {
      if (store instanceof IncrementalStore) {
        return store.execute(request, context, function(err) {
          var i, object, ref1;
          if (err) {
            ref1 = context.insertedObjects;
            for (i in ref1) {
              object = ref1[i];
              object._objectID = temporaryObjectIDs[i];
            }
          }
          return cb(err);
        }, (function(_this) {
          return function() {
            var i, object, permanentObjectIDs, ref1, results;
            permanentObjectIDs = store.permanentIDsForObjects(context.insertedObjects);
            ref1 = context.insertedObjects;
            results = [];
            for (i in ref1) {
              object = ref1[i];
              temporaryObjectIDs[i] = object._objectID;
              results.push(object._objectID = permanentObjectIDs[i]);
            }
            return results;
          };
        })(this));
      } else {
        return cb(new Error('not an incremental store'));
      }
    }, (function(_this) {
      return function(err) {
        return callback(err);
      };
    })(this));
  };

  PersistentStoreCoordinator.prototype._valuesForForRelationship = function(relationship, ObjectID, context, callback) {
    var inversedRelationship, request;
    inversedRelationship = relationship.inverseRelationship();
    request = new FetchRequest(inversedRelationship.entity, new Predicate('SELF.' + inversedRelationship.name + '._id = %d', ObjectID.recordId()));
    return this.execute(request, context, callback);
  };

  PersistentStoreCoordinator.prototype.temporaryObjectID = function(object) {
    var id;
    id = this.persistentStores[0].newObjectID(object.entity, this.temporaryId++);
    id.isTemporaryID = true;
    return id;
  };

  Object.defineProperties(PersistentStoreCoordinator.prototype, {
    registeredStoreTypes: {
      get: function() {
        return registeredStoreTypes;
      }
    }
  });

  return PersistentStoreCoordinator;

})(Object);

module.exports = PersistentStoreCoordinator;
