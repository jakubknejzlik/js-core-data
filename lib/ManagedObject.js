const ManagedObjectID = require("./ManagedObjectID");
const RelationshipDescription = require("./Descriptors/RelationshipDescription");
const ac = require("array-control");
const Promise = require("bluebird");
const async = require("async");
const util = require("util");

const _ = require("underscore");
_.mixin(require("underscore.inflections"));

const capitalizedString = function(string) {
  return string[0].toUpperCase() + string.substring(1);
};

class ManagedObject extends Object {
  constructor(entity, managedObjectContext, _rawData) {
    super();
    this.entity = entity;
    this.managedObjectContext = managedObjectContext;
    this._rawData = _rawData;
    this.context = this.managedObjectContext;
    this._objectID = null;
    this._isInserted = false;
    this._isDeleted = false;
    this._isFault = true;
    this._data = null;
    this._changes = null;
    this._relationChanges = null;
  }

  fetchData() {
    var data = {};
    if (this._rawData) {
      for (let attribute of this.entity.attributes) {
        data[attribute.name] = attribute.transform(
          this._rawData[attribute.name]
        );
      }
      for (let relationship of this.entity.relationships) {
        data[relationship.name + "_id"] = this._rawData[
          relationship.name + "_id"
        ];
      }
    }
    delete this._rawData;
    this._data = data;
    this._isFault = false;
  }

  validateValueForKey(value, key) {
    let attributeDescription = this.entity.attributesByName()[key];
    return attributeDescription.validateValue(value);
  }

  setValues(values, allowedAttributes, options) {
    if (!Array.isArray(allowedAttributes)) {
      options = allowedAttributes || {};
      allowedAttributes = null;
    }
    for (let attributeDescription of this.entity.attributes) {
      if (
        values &&
        typeof values[attributeDescription.name] !== "undefined" &&
        (!allowedAttributes ||
          ~allowedAttributes.indexOf(attributeDescription.name)) &&
        (!attributeDescription.isPrivate() ||
          (options && options.privates) ||
          (allowedAttributes &&
            ~allowedAttributes.indexOf(attributeDescription.name)))
      ) {
        this[attributeDescription.name] = values[attributeDescription.name];
      }
    }
  }

  getValues(allowedAttributes, options) {
    if (options == null) {
      options = {};
    }
    if (!Array.isArray(allowedAttributes)) {
      options = allowedAttributes || {};
      allowedAttributes = options.attributes || null;
    }
    if (this.isFault) {
      this.fetchData();
    }
    var values = {
      id: this.objectID.recordId()
    };
    for (let attributeDescription of this.entity.attributes) {
      if (
        (!allowedAttributes ||
          ((ref1 = attributeDescription.name),
          allowedAttributes.indexOf(ref1) >= 0)) &&
        (!attributeDescription.isPrivate() || options.privates)
      ) {
        let value = this[attributeDescription.name];
        if (value != null) {
          values[attributeDescription.name] = value;
        } else {
          values[attributeDescription.name] = null;
        }
      }
    }
    if (!options.noRelations) {
      for (let relationship of this.entity.relationships) {
        if (!relationship.toMany) {
          let getterFnName =
            "get" + capitalizedString(_.singularize(relationship.name)) + "ID";
          let value = this[getterFnName]();
          if (value !== null) {
            values[_.singularize(relationship.name) + "_id"] = value;
          } else {
            values[_.singularize(relationship.name) + "_id"] = null;
          }
        }
      }
    }
    return values;
  }

  toJSON(options) {
    return this.getValues(options);
  }

  static addAttributeDescription(obj, attributeDescription) {
    let capitalizedName = capitalizedString(attributeDescription.name);
    if (!attributeDescription.isTransient()) {
      obj.prototype["get" + capitalizedName] =
        obj.prototype["get" + capitalizedName] ||
        function() {
          return this["_get" + capitalizedName]();
        };
      obj.prototype["set" + capitalizedName] =
        obj.prototype["set" + capitalizedName] ||
        function(value) {
          return this["_set" + capitalizedName](value);
        };
      obj.prototype["_get" + capitalizedName] = function() {
        var value;
        if (this.isFault) {
          this.fetchData();
        }
        value = this._data[attributeDescription.name];
        if (value === void 0) {
          return null;
        }
        return value;
      };
      obj.prototype["_set" + capitalizedName] = function(value) {
        if (this.isFault) {
          this.fetchData();
        }
        if (value !== this._data[attributeDescription.name]) {
          if (typeof this["validate" + capitalizedName] === "function") {
            if (!this["validate" + capitalizedName](value)) {
              throw new Error(
                "value '" +
                  value +
                  "' (" +
                  typeof value +
                  ") is not valid for attribute " +
                  attributeDescription.name
              );
            }
          }
          this["_validate" + capitalizedName](value);
          value = attributeDescription.transform(value);
          this._data[attributeDescription.name] = value;
          this._changes = this._changes || {};
          this._changes[attributeDescription.name] = value;
          this._didUpdateValues();
        }
        return this;
      };
      obj.prototype["_validate" + capitalizedName] = function(value) {
        return this.validateValueForKey(value, attributeDescription.name);
      };
    }
    return ManagedObject.bindAttributeDescription(obj, attributeDescription);
  }

  static bindAttributeDescription(obj, attributeDescription) {
    let capitalizedName =
      attributeDescription.name[0].toUpperCase() +
      attributeDescription.name.substring(1);
    return Object.defineProperty(obj.prototype, attributeDescription.name, {
      get: obj.prototype["get" + capitalizedName],
      set: obj.prototype["set" + capitalizedName]
    });
  }

  static addRelationshipDescription(obj, relationshipDescription) {
    let singularizedName = _.singularize(relationshipDescription.name);
    let capitalizedSingularizedName =
      singularizedName[0].toUpperCase() + singularizedName.substring(1);
    let capitalizedName =
      relationshipDescription.name[0].toUpperCase() +
      relationshipDescription.name.substring(1);
    let inverseRelationship = relationshipDescription.inverseRelationship();
    let inverseRelationshipCapitalizedName =
      inverseRelationship.name[0].toUpperCase() +
      inverseRelationship.name.substring(1);
    if (!relationshipDescription.toMany) {
      obj.prototype["get" + capitalizedName] =
        obj.prototype["get" + capitalizedName] ||
        function(callback) {
          return this["_get" + capitalizedName](callback);
        };
      obj.prototype["set" + capitalizedName] =
        obj.prototype["set" + capitalizedName] ||
        function(object) {
          return this["_set" + capitalizedName](object);
        };
      obj.prototype["get" + capitalizedSingularizedName + "ID"] = function() {
        var ref, ref1;
        if (this.isFault) {
          this.fetchData();
        }
        return (
          this._data[singularizedName + "_id"] ||
          ((ref = this._data[relationshipDescription.name]) != null
            ? (ref1 = ref.objectID) != null ? ref1.recordId() : void 0
            : void 0) ||
          null
        );
      };
      obj.prototype["_get" + capitalizedName] = function(callback) {
        return new Promise((resolve, reject) => {
          if (this.isFault) {
            this.fetchData();
          }
          return async.nextTick(() => {
            if (
              typeof this._data[relationshipDescription.name] === "undefined"
            ) {
              return this.managedObjectContext._getObjectsForRelationship(
                relationshipDescription,
                this,
                this.managedObjectContext,
                function(err, objects) {
                  if (err) {
                    return reject(err);
                  } else {
                    return resolve(objects[0] || null);
                  }
                }
              );
            } else {
              return resolve(this._data[relationshipDescription.name]);
            }
          });
        }).asCallback(callback);
      };
      obj.prototype["_set" + capitalizedName] = function(object) {
        if (object !== null && !(object instanceof ManagedObject)) {
          throw new Error(
            "only ManagedObject instances or null can be set to relationship (given " +
              util.format(object) +
              "; " +
              relationshipDescription.entity.name +
              "=>" +
              relationshipDescription.name +
              ")"
          );
        }
        return this._setObjectToRelation(
          object,
          relationshipDescription,
          inverseRelationship
        );
      };
    } else {
      obj.prototype["get" + capitalizedName] =
        obj.prototype["get" + capitalizedName] ||
        function(callback) {
          return this["_get" + capitalizedName](callback);
        };
      obj.prototype["add" + capitalizedSingularizedName] =
        obj.prototype["add" + capitalizedSingularizedName] ||
        function(object) {
          return this["_add" + capitalizedSingularizedName](object);
        };
      obj.prototype["add" + capitalizedName] =
        obj.prototype["add" + capitalizedName] ||
        function(objects) {
          return this["_add" + capitalizedName](objects);
        };
      obj.prototype["remove" + capitalizedSingularizedName] =
        obj.prototype["remove" + capitalizedSingularizedName] ||
        function(object) {
          return this["_remove" + capitalizedSingularizedName](object);
        };
      obj.prototype["remove" + capitalizedName] =
        obj.prototype["remove" + capitalizedName] ||
        function(objects) {
          return this["_remove" + capitalizedName](objects);
        };
      obj.prototype["_get" + capitalizedName] = obj.prototype[
        "get" + capitalizedSingularizedName + "Objects"
      ] = function(callback) {
        return new Promise((resolve, reject) => {
          if (this.isFault) {
            this.fetchData();
          }
          if (!Array.isArray(this._data[relationshipDescription.name])) {
            return this.managedObjectContext._getObjectsForRelationship(
              relationshipDescription,
              this,
              this.managedObjectContext,
              (err, objects) => {
                if (err) {
                  return reject(err);
                }
                if (this._relationChanges) {
                  let addedChanges = this._relationChanges[
                    "added_" + relationshipDescription.name
                  ];
                  if (addedChanges) {
                    for (let item of addedChanges) {
                      ac.addObject(objects, item);
                    }
                  }
                  let removedChanges = this._relationChanges[
                    "removed_" + relationshipDescription.name
                  ];
                  if (removedChanges) {
                    for (let item of removedChanges) {
                      item = ref1[j];
                      ac.removeObject(objects, item);
                    }
                  }
                }
                this._data[relationshipDescription.name] = objects;
                return resolve(
                  this._data[relationshipDescription.name].slice(0)
                );
              }
            );
          } else {
            return resolve(this._data[relationshipDescription.name].slice(0));
          }
        }).asCallback(callback);
      };
      obj.prototype["_add" + capitalizedSingularizedName] = function(object) {
        if (!(object instanceof ManagedObject)) {
          throw new Error(
            "only ManagedObject instances can be added to toMany relationship (given " +
              util.format(object) +
              "; " +
              relationshipDescription.entity.name +
              "=>" +
              relationshipDescription.name +
              ")"
          );
        }
        return this._addObjectToRelation(
          object,
          relationshipDescription,
          inverseRelationship
        );
      };
      obj.prototype["_add" + capitalizedName] = obj.prototype[
        "add" + capitalizedSingularizedName + "Objects"
      ] = function(objects) {
        if (!Array.isArray(objects)) {
          throw new Error(
            "array must be specified in addObjects method (given " +
              util.format(objects) +
              "; " +
              relationshipDescription.entity.name +
              "=>" +
              relationshipDescription.name +
              ")"
          );
        }
        let results = [];
        for (let object of objects) {
          results.push(this["add" + capitalizedSingularizedName](object));
        }
        return results;
      };
      obj.prototype["_remove" + capitalizedSingularizedName] = function(
        object
      ) {
        if (!(object instanceof ManagedObject)) {
          throw new Error(
            "only ManagedObject instances can be removed from toMany relationship (given " +
              util.format(object) +
              "; " +
              relationshipDescription.entity.name +
              "=>" +
              relationshipDescription.name +
              ")"
          );
        }
        return this._removeObjectFromRelation(
          object,
          relationshipDescription,
          inverseRelationship
        );
      };
      obj.prototype["_remove" + capitalizedName] = obj.prototype[
        "remove" + capitalizedSingularizedName + "Objects"
      ] = function(objects) {
        var i, len, object, results;
        if (!Array.isArray(objects)) {
          throw new Error(
            "array must be specified in removeObjects method (given " +
              util.format(objects) +
              "; " +
              relationshipDescription.entity.name +
              "=>" +
              relationshipDescription.name +
              ")"
          );
        }
        results = [];
        for (i = 0, len = objects.length; i < len; i++) {
          object = objects[i];
          results.push(this["remove" + capitalizedSingularizedName](object));
        }
        return results;
      };
    }
    return obj;
  }

  awakeFromInsert() {}

  awakeFromFetch() {}

  willSave() {
    for (let attribute of this.entity.getNonTransientAttributes()) {
      if (attribute.info.required && this[attribute.name] === null) {
        throw new Error(
          "cannot save " +
            this.entity.name +
            ", attribute " +
            attribute.name +
            " is required"
        );
      }
    }
  }

  didSave() {}

  prepareForDeletion(callback) {
    return callback();
  }

  _setObjectToRelation(
    object,
    relationshipDescription,
    inversedRelationshipDescription,
    noRecursion
  ) {
    if (this.isFault) {
      this.fetchData();
    }
    if (object && object.managedObjectContext !== this.managedObjectContext) {
      throw new Error(
        "cannot set object to relationship of object in different context"
      );
    }
    if (object !== this._data[relationshipDescription.name]) {
      let prevObject = this._data[relationshipDescription.name];
      let singularizedName = _.singularize(relationshipDescription.name);
      this._data[relationshipDescription.name] = object;
      delete this._data[singularizedName + "_id"];
      this._relationChanges = this._relationChanges || {};
      this._relationChanges[relationshipDescription.name] = object;
      if (inversedRelationshipDescription) {
        if (inversedRelationshipDescription.toMany) {
          if (object === null && prevObject) {
            prevObject._removeObjectFromRelation(
              this,
              inversedRelationshipDescription,
              relationshipDescription,
              true
            );
          } else if (object !== null) {
            object._addObjectToRelation(
              this,
              inversedRelationshipDescription,
              relationshipDescription,
              true
            );
          }
        } else if (!noRecursion) {
          object._setObjectToRelation(
            this,
            inversedRelationshipDescription,
            relationshipDescription,
            true
          );
        }
      }
      return this._didUpdateValues();
    }
  }

  _addObjectToRelation(
    object,
    relationshipDescription,
    inversedRelationshipDescription,
    noRecursion
  ) {
    if (this.isFault) {
      this.fetchData();
    }
    if (object && object.managedObjectContext !== this.managedObjectContext) {
      throw new Error(
        "cannot add object to relationship of object in different context"
      );
    }
    if (
      !this._data[relationshipDescription.name] ||
      this._data[relationshipDescription.name].indexOf(object) < 0
    ) {
      this._relationChanges = this._relationChanges || {};
      this._relationChanges["added_" + relationshipDescription.name] =
        this._relationChanges["added_" + relationshipDescription.name] || [];
      this._relationChanges["removed_" + relationshipDescription.name] =
        this._relationChanges["removed_" + relationshipDescription.name] || [];
      this._data[relationshipDescription.name] =
        this._data[relationshipDescription.name] || [];
      ac.addObject(this._data[relationshipDescription.name], object);
      if (
        this._relationChanges[
          "removed_" + relationshipDescription.name
        ].indexOf(object) < 0
      ) {
        ac.addObject(
          this._relationChanges["added_" + relationshipDescription.name],
          object
        );
      }
      if (this._relationChanges["removed_" + relationshipDescription.name]) {
        ac.removeObject(
          this._relationChanges["removed_" + relationshipDescription.name],
          object
        );
      }
      if (inversedRelationshipDescription && !noRecursion) {
        if (!inversedRelationshipDescription.toMany) {
          object._setObjectToRelation(this, inversedRelationshipDescription);
        } else {
          object._addObjectToRelation(
            this,
            inversedRelationshipDescription,
            relationshipDescription,
            true
          );
        }
      }
      return this._didUpdateValues();
    }
  }

  _removeObjectFromRelation(
    object,
    relationshipDescription,
    inversedRelationshipDescription,
    noRecursion,
    fireEvent
  ) {
    if (fireEvent == null) {
      fireEvent = true;
    }
    if (this.isFault) {
      this.fetchData();
    }
    if (object && object.managedObjectContext !== this.managedObjectContext) {
      throw new Error(
        "cannot remove object from relationship of object in different context"
      );
    }
    if (
      !this._data[relationshipDescription.name] ||
      this._data[relationshipDescription.name].indexOf(object) >= 0
    ) {
      this._relationChanges = this._relationChanges || {};
      this._relationChanges["added_" + relationshipDescription.name] =
        this._relationChanges["added_" + relationshipDescription.name] || [];
      this._relationChanges["removed_" + relationshipDescription.name] =
        this._relationChanges["removed_" + relationshipDescription.name] || [];
      if (this._data[relationshipDescription.name]) {
        ac.removeObject(this._data[relationshipDescription.name], object);
      }
      if (
        this._relationChanges["added_" + relationshipDescription.name].indexOf(
          object
        ) < 0
      ) {
        ac.addObject(
          this._relationChanges["removed_" + relationshipDescription.name],
          object
        );
      }
      if (this._relationChanges["added_" + relationshipDescription.name]) {
        ac.removeObject(
          this._relationChanges["added_" + relationshipDescription.name],
          object
        );
      }
      if (inversedRelationshipDescription && !noRecursion) {
        if (!inversedRelationshipDescription.toMany) {
          object._setObjectToRelation(null, inversedRelationshipDescription);
        } else {
          object._removeObjectFromRelation(
            this,
            inversedRelationshipDescription,
            relationshipDescription,
            true
          );
        }
      }
      if (fireEvent) {
        return this._didUpdateValues();
      }
    }
  }

  _didUpdateValues() {
    return this.managedObjectContext._didUpdateObject(this);
  }
}

Object.defineProperties(ManagedObject.prototype, {
  id: {
    get: function() {
      return this._objectID.recordId();
    },
    set: function(value) {
      return this._objectID.setRecordId(value);
    }
  },
  objectID: {
    get: function() {
      return this._objectID;
    }
  },
  hasChanges: {
    get: function() {
      return this.isUpdated || this.isInserted || this.isDeleted;
    }
  },
  isInserted: {
    get: function() {
      return this._isInserted;
    }
  },
  isUpdated: {
    get: function() {
      return !!(
        (this._changes && Object.keys(this._changes).length > 0) ||
        (this._relationChanges && this._relationChanges.length > 0)
      );
    }
  },
  isDeleted: {
    get: function() {
      return this._isDeleted;
    }
  },
  isFault: {
    get: function() {
      return this._isFault;
    }
  }
});

module.exports = ManagedObject;
