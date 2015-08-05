// Generated by CoffeeScript 1.9.3
(function() {
  var AttributeDescription, CoreData, EntityDescription, ManagedObject, ManagedObjectContext, ManagedObjectModel, PersistentStoreCoordinator, Pool, Predicate, RelationshipDescription, async, url;

  PersistentStoreCoordinator = require('./lib/PersistentStoreCoordinator');

  ManagedObjectModel = require('./lib/ManagedObjectModel');

  ManagedObjectContext = require('./lib/ManagedObjectContext');

  ManagedObject = require('./lib/ManagedObject');

  Predicate = require('./lib/FetchClasses/Predicate');

  EntityDescription = require('./lib/Descriptors/EntityDescription');

  AttributeDescription = require('./lib/Descriptors/AttributeDescription');

  RelationshipDescription = require('./lib/Descriptors/RelationshipDescription');

  Pool = require('generic-pool');

  url = require('url');

  async = require('async');

  CoreData = (function() {
    function CoreData(storeURL1, options) {
      this.storeURL = storeURL1;
      if (options == null) {
        options = {};
      }
      this.model = new ManagedObjectModel(options.modelFile, options.modelClasses);
    }

    CoreData.prototype.syncSchema = function(options, callback) {
      if (typeof options === 'function') {
        callback = options;
        options = void 0;
      }
      options = options || {};
      return async.forEach(this._persistentStoreCoordinator().persistentStores, function(store, cb) {
        return store.syncSchema(options, cb);
      }, callback);
    };

    CoreData.prototype.defineEntity = function(entityName, attributes, options) {
      var attr, attributeInfo, attributeKey, entity;
      if (options == null) {
        options = {};
      }
      entity = new EntityDescription(entityName);
      if (options["class"]) {
        entity.objectClassName = options["class"];
      }
      for (attributeKey in attributes) {
        attributeInfo = attributes[attributeKey];
        if (!(attributeInfo instanceof Object)) {
          attributeInfo = {
            type: attributeInfo
          };
        }
        attr = new AttributeDescription(attributeInfo.type, attributeInfo, attributeKey, null);
        if (attributeInfo.options) {
          attr.options = attributeInfo.options;
        }
        entity.addAttribute(attr);
      }
      this.model.addEntity(entity);
      return entity;
    };

    CoreData.prototype.defineRelationship = function(entity, destinationEntity, name, options) {
      var relationship;
      if (options == null) {
        options = {};
      }
      if (typeof entity === 'string') {
        entity = this.model.entities[entity];
      }
      if (typeof destinationEntity === 'string') {
        destinationEntity = this.model.entities[destinationEntity];
      }
      relationship = new RelationshipDescription(name, destinationEntity, options.toMany, options.inverse, entity);
      return entity.addRelationship(relationship);
    };

    CoreData.prototype.createContext = function() {
      return new ManagedObjectContext(this._persistentStoreCoordinator());
    };

    CoreData.prototype._persistentStoreCoordinator = function() {
      if (!this.persistentStoreCoordinator) {
        this.persistentStoreCoordinator = new PersistentStoreCoordinator(this.model);
        this.persistentStoreCoordinator.addStore(this.storeURL);
      }
      return this.persistentStoreCoordinator;
    };

    CoreData.prototype.middleware = function() {};

    return CoreData;

  })();

  CoreData.PersistentStoreCoordinator = PersistentStoreCoordinator;

  CoreData.ManagedObjectModel = ManagedObjectModel;

  CoreData.ManagedObjectContext = ManagedObjectContext;

  CoreData.ManagedObject = ManagedObject;

  CoreData.Predicate = Predicate;

  CoreData.debug = process.env.NOD_ENV !== 'production';

  module.exports = CoreData;

  CoreData.createContextPool = function(modelFile, storeURL, options, callback) {
    var createAndSendPool, objectModel, persistentStoreCoordinator;
    createAndSendPool = function() {
      var pool;
      options = options || {};
      options.name = 'model:' + modelFile + ';store:' + storeURL;
      options.max = options.max || 10;
      options.idleTimeoutMillis = options.idleTimeoutMillis || 1000;
      options.create = function(callback) {
        callback(null, new ManagedObjectContext(persistentStoreCoordinator));
      };
      options.destroy = function(context) {
        context.destroy();
      };
      pool = new Pool.Pool(options);
      pool.runBlockWithCallback = (function(callback, fn) {
        return pool.acquire(function(err, context) {
          if (err) {
            return callback(err);
          }
          return fn(context, function() {
            pool.release(context);
            return callback.apply(this, arguments);
          });
        });
      });
      callback(null, pool);
    };
    options = options || {};
    objectModel = new ManagedObjectModel(modelFile, options.modelClasses);
    persistentStoreCoordinator = new PersistentStoreCoordinator(objectModel);
    if (storeURL.indexOf('mysql:') === 0) {
      persistentStoreCoordinator.addStore(PersistentStoreCoordinator.STORE_TYPE_MYSQL, storeURL, function(err) {
        if (err) {
          return callback(err);
        }
        return createAndSendPool();
      });
    } else {
      callback(new Error('unknown store for url' + storeURL));
    }
  };

  CoreData.ExpressJS = {
    middleware: function(contextPool) {
      return function(req, res, next) {
        contextPool.acquire(function(err, context) {
          if (err) {
            return next(err);
          }
          req.context = context;
          res.on('finish', function() {
            contextPool.release(context);
          });
          next();
        });
      };
    },
    errorReleaseHandler: function(contextPool) {
      return function(err, req, res, next) {
        if (req.context) {
          contextPool.release(req.context);
        }
        next(err);
      };
    }
  };

}).call(this);
