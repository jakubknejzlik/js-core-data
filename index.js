// Generated by CoffeeScript 1.10.0
(function() {
  var AttributeDescription, AttributeType, CoreData, EntityDescription, ManagedObject, ManagedObjectContext, ManagedObjectModel, ModelYamlParser, PersistentStoreCoordinator, Pool, Predicate, Promise, RelationshipDescription, async, convert, url;

  PersistentStoreCoordinator = require('./lib/PersistentStoreCoordinator');

  ManagedObjectModel = require('./lib/ManagedObjectModel');

  ManagedObjectContext = require('./lib/ManagedObjectContext');

  ManagedObject = require('./lib/ManagedObject');

  Predicate = require('./lib/FetchClasses/Predicate');

  EntityDescription = require('./lib/Descriptors/EntityDescription');

  AttributeDescription = require('./lib/Descriptors/AttributeDescription');

  AttributeType = require('./lib/Descriptors/AttributeType');

  RelationshipDescription = require('./lib/Descriptors/RelationshipDescription');

  ModelYamlParser = require('./lib/Parsers/ModelYamlParser');

  Pool = require('generic-pool');

  url = require('url');

  async = require('async');

  Promise = require('bluebird');

  convert = require('unit-converter');

  CoreData = (function() {
    CoreData.registerType = function(type) {
      return AttributeDescription.registerType(type);
    };

    function CoreData(storeURL, options1) {
      this.storeURL = storeURL;
      this.options = options1 != null ? options1 : {};
      this.modelVersion = 'default';
      if (this.options.logging && typeof this.options.logging !== 'function') {
        this.options.logging = console.log;
      }
      this.models = {};
    }

    CoreData.prototype.syncSchema = function(options, callback) {
      if (typeof options === 'function') {
        callback = options;
        options = void 0;
      }
      return new Promise((function(_this) {
        return function(resolve, reject) {
          options = options || {};
          return async.forEach(_this._persistentStoreCoordinator().persistentStores, function(store, cb) {
            return store.syncSchema(options, cb);
          }, function(err) {
            if (err) {
              return reject(err);
            } else {
              return resolve();
            }
          });
        };
      })(this)).asCallback(callback);
    };

    CoreData.prototype.closeAllConnections = function() {
      return new Promise((function(_this) {
        return function(resolve, reject) {
          return async.forEach(_this._persistentStoreCoordinator().persistentStores, function(store, cb) {
            return store.closeAllConnections(cb);
          }, function(err) {
            if (err) {
              return reject(err);
            }
            return resolve();
          });
        };
      })(this));
    };

    CoreData.prototype._ensureModel = function() {
      if (!this.model) {
        this.model = this.createModel();
      }
      return this.model;
    };

    CoreData.prototype.setModelVersion = function(version) {
      if (!this.models[version]) {
        throw new Error('unknown model version ' + version);
      }
      this.modelVersion = version;
      this.model = this.models[this.modelVersion];
      return this.persistentStoreCoordinator = null;
    };

    CoreData.prototype.createModelFromYaml = function(yamlSource, objectClasses, modelVersion) {
      var model;
      modelVersion = modelVersion || this.modelVersion;
      model = this.createModel(modelVersion);
      ModelYamlParser.fillModelFromYaml(model, yamlSource, objectClasses);
      return model;
    };

    CoreData.prototype.createModel = function(modelVersion) {
      modelVersion = modelVersion || this.modelVersion;
      this.models[modelVersion] = new ManagedObjectModel(modelVersion);
      if (!this.model) {
        this.model = this.models[modelVersion];
      }
      return this.models[modelVersion];
    };

    CoreData.prototype.getModel = function(modelVersion) {
      if (!this.models[modelVersion]) {
        throw new Error('model with version ' + modelVersion + ' not found');
      }
      return this.models[modelVersion];
    };

    CoreData.prototype.defineEntity = function(entityName, attributes, options) {
      if (options == null) {
        options = {};
      }
      return this._ensureModel().defineEntity(entityName, attributes, options);
    };

    CoreData.prototype.defineRelationship = function(entity, destinationEntity, name, options) {
      if (options == null) {
        options = {};
      }
      return this._ensureModel().defineRelationship(entity, destinationEntity, name, options);
    };

    CoreData.prototype.defineRelationshipToMany = function(entity, destinationEntity, name, inverse, options) {
      return this._ensureModel().defineRelationshipToMany(entity, destinationEntity, name, inverse, options);
    };

    CoreData.prototype.defineRelationshipToOne = function(entity, destinationEntity, name, inverse, options) {
      return this._ensureModel().defineRelationshipToOne(entity, destinationEntity, name, inverse, options);
    };

    CoreData.prototype.defineRelationshipOneToMany = function(entity, destinationEntity, name, inverse, options) {
      return this._ensureModel().defineRelationshipOneToMany(entity, destinationEntity, name, inverse, options);
    };

    CoreData.prototype.defineRelationshipManyToOne = function(entity, destinationEntity, name, inverse, options) {
      return this._ensureModel().defineRelationshipManyToOne(entity, destinationEntity, name, inverse, options);
    };

    CoreData.prototype.defineRelationshipManyToMany = function(entity, destinationEntity, name, inverse, options) {
      return this._ensureModel().defineRelationshipManyToMany(entity, destinationEntity, name, inverse, options);
    };

    CoreData.prototype.createContext = function() {
      return new ManagedObjectContext(this._persistentStoreCoordinator());
    };

    CoreData.prototype._persistentStoreCoordinator = function() {
      if (!this.persistentStoreCoordinator) {
        this.persistentStoreCoordinator = new PersistentStoreCoordinator(this.model, this.options);
        this.persistentStoreCoordinator.addStore(this.storeURL);
      }
      return this.persistentStoreCoordinator;
    };

    CoreData.prototype.middleware = function(options) {
      var destroyTimeout;
      options = options || {};
      destroyTimeout = convert(options.destroyTimeout || '10s').to('ms');
      return (function(_this) {
        return function(req, res, next) {
          var context;
          if (_this.options.logging) {
            _this.options.logging('creating context');
          }
          context = _this.createContext();
          req.context = context;
          res.once('close', function() {
            if (context.destroyed) {
              return;
            }
            if (_this.options.logging) {
              _this.options.logging('destroying context timeout (close): ', destroyTimeout);
            }
            return setTimeout(function() {
              return context.destroy();
            }, destroyTimeout);
          });
          res.once('finish', function() {
            if (context.destroyed) {
              return;
            }
            if (_this.options.logging) {
              _this.options.logging('destroying context timeout (finish): ', destroyTimeout);
            }
            return setTimeout(function() {
              return context.destroy();
            }, destroyTimeout);
          });
          return next();
        };
      })(this);
    };

    return CoreData;

  })();

  CoreData.PersistentStoreCoordinator = PersistentStoreCoordinator;

  CoreData.ManagedObjectModel = ManagedObjectModel;

  CoreData.ManagedObjectContext = ManagedObjectContext;

  CoreData.ManagedObject = ManagedObject;

  CoreData.Predicate = Predicate;

  CoreData.AttributeType = AttributeType;

  CoreData.debug = process.env.NOD_ENV !== 'production';

  module.exports = CoreData;

}).call(this);
