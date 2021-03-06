var CoreData, Promise;

Promise = require("bluebird");

CoreData = require("../CoreData");

CoreData.prototype.syncSchema = function(options, callback) {
  if (typeof options === "function") {
    callback = options;
    options = void 0;
  }
  options = options || {};
  return Promise.each(
    this._persistentStoreCoordinator().persistentStores,
    (function(_this) {
      return function(store) {
        return _this.syncStoreSchema(store, options);
      };
    })(this)
  )
    .thenReturn(null)
    .asCallback(callback);
};

CoreData.prototype.syncStoreSchema = function(store, options) {
  var objectModel;
  objectModel = this.model;
  return store.getCurrentVersion().then(
    (function(_this) {
      return function(databaseModelVersion) {
        var databaseModel, migrations;
        if (databaseModelVersion === objectModel.version && !options.force) {
          return null;
        } else if (
          !databaseModelVersion &&
          !options.ignoreMissingVersion &&
          !options.force
        ) {
          throw new Error(
            "current version not found, rerun syncSchema with enabled option ignoreMissingVersion"
          );
        } else if (
          (!databaseModelVersion && options.ignoreMissingVersion) ||
          options.force
        ) {
          return store.syncSchema(options);
        } else {
          migrations = objectModel.getMigrationsFrom(databaseModelVersion);
          if (!migrations || migrations.length === 0) {
            if (options.automigration) {
              databaseModel = _this.getModel(databaseModelVersion);
              migrations = [
                objectModel.autogenerateMigrationFromModel(
                  databaseModel,
                  options
                )
              ];
            } else {
              throw new Error(
                "migration " +
                  databaseModelVersion +
                  "=>" +
                  objectModel.version +
                  " not found"
              );
            }
          }
          return Promise.each(migrations, function(migration) {
            return store.runMigration(migration);
          });
        }
      };
    })(this)
  );
};
