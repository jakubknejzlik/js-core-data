var ManagedObjectID,
  extend = function(child, parent) {
    for (var key in parent) {
      if (hasProp.call(parent, key)) child[key] = parent[key];
    }
    function ctor() {
      this.constructor = child;
    }
    ctor.prototype = parent.prototype;
    child.prototype = new ctor();
    child.__super__ = parent.prototype;
    return child;
  },
  hasProp = {}.hasOwnProperty;

ManagedObjectID = (function(superClass) {
  extend(ManagedObjectID, superClass);

  function ManagedObjectID(stringValue, entity) {
    this.stringValue = stringValue;
    this.entity = entity;
    this.stringValue = this.stringValue + "";
    this.isTemporaryID = false;
  }

  ManagedObjectID.idColumnName = "id";

  ManagedObjectID.prototype.isEqual = function(objectID) {
    return this.toString() === objectID.toString();
  };

  ManagedObjectID.prototype.toString = function() {
    return this.stringValue;
  };

  ManagedObjectID.prototype.recordId = function() {
    var ID, components;
    components = this.stringValue.split("/");
    ID = components[components.length - 1];
    return parseInt(ID.replace(/^[pt]/, ""));
  };

  ManagedObjectID.prototype.setRecordId = function(recordId) {
    var ID, components;
    components = this.stringValue.split("/");
    ID = components[components.length - 1];
    if (ID[0] != "t") {
      throw new Error("cannot change ID for permanent object");
    }
    components[components.length - 1] = `p${recordId}`; // switch this ID to be persisted
    this.stringValue = components.join("/");
    this.isTemporaryID = false;
  };

  return ManagedObjectID;
})(Object);

module.exports = ManagedObjectID;
