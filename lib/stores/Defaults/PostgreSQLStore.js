// Generated by CoffeeScript 1.10.0
(function() {
  var GenericPool, GenericSQLStore, ManagedObjectID, PersistentStoreRequest, PostgreSQLConnection, PostgreSQLStore, Predicate, SQLConnection, SQLTransaction, _, async, e, error, pg,
    extend = function(child, parent) { for (var key in parent) { if (hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
    hasProp = {}.hasOwnProperty;

  GenericSQLStore = require('./GenericSQLStore');

  PersistentStoreRequest = require('./../PersistentStoreRequest');

  GenericPool = require('generic-pool');

  async = require('async');

  ManagedObjectID = require('./../../ManagedObjectID');

  Predicate = require('./../../FetchClasses/Predicate');

  SQLConnection = require('./SQLConnection');

  SQLTransaction = require('./SQLTransaction');

  try {
    require('pg');
  } catch (error) {
    e = error;
    throw new Error('pg module is required to user SQLite storage, please install it by running npm install --save pg');
  }

  pg = require('pg');

  _ = require('underscore');

  _.mixin(require('underscore.inflections'));

  PostgreSQLStore = (function(superClass) {
    extend(PostgreSQLStore, superClass);

    function PostgreSQLStore() {
      return PostgreSQLStore.__super__.constructor.apply(this, arguments);
    }

    PostgreSQLStore.prototype.createConnection = function() {
      return new PostgreSQLConnection(this.URL, this);
    };

    PostgreSQLStore.prototype.createSchemaQueries = function(options) {
      var entity, key, objectModel, ref, sqls;
      if (options == null) {
        options = {};
      }
      objectModel = this.storeCoordinator.objectModel;
      sqls = [];
      ref = objectModel.entities;
      for (key in ref) {
        entity = ref[key];
        sqls = sqls.concat(this.createEntityQueries(entity, options.force));
      }
      sqls.push('CREATE TABLE IF NOT EXISTS "_meta" ("key" varchar(10) NOT NULL,"value" varchar(250) NOT NULL,PRIMARY KEY ("key"))');
      sqls.push('DELETE FROM "_meta" WHERE ' + this.quoteSymbol + 'key' + this.quoteSymbol + ' = \'version\'');
      sqls.push('INSERT INTO "_meta" VALUES(\'version\',\'' + objectModel.version + '\')');
      return sqls;
    };

    PostgreSQLStore.prototype.createEntityQueries = function(entity, force, options) {
      var attribute, columnDefinition, i, index, j, k, len, len1, len2, parts, ref, ref1, ref2, relationship, sql, sqls, tableName;
      if (force == null) {
        force = false;
      }
      if (options == null) {
        options = {};
      }
      sqls = [];
      tableName = this._formatTableName(entity.name);
      parts = ['"_id" SERIAL PRIMARY KEY'];
      ref = entity.attributes;
      for (i = 0, len = ref.length; i < len; i++) {
        attribute = ref[i];
        columnDefinition = this._columnDefinitionForAttribute(attribute);
        if (columnDefinition) {
          parts.push(columnDefinition);
        } else {
          throw new Error('unknown attribute type ' + attribute.type);
        }
      }
      ref1 = entity.relationships;
      for (j = 0, len1 = ref1.length; j < len1; j++) {
        relationship = ref1[j];
        if (!relationship.toMany) {
          parts.push('"' + relationship.name + '_id" int DEFAULT NULL');
        }
      }
      if (force) {
        sqls.push('DROP TABLE IF EXISTS "' + tableName + '"');
      }
      sql = 'CREATE TABLE IF NOT EXISTS "' + tableName + '" (';
      sql += parts.join(',');
      sql += ')';
      ref2 = this._indexesForEntity(entity);
      for (k = 0, len2 = ref2.length; k < len2; k++) {
        index = ref2[k];
        sql += ';CREATE ' + (index.type === 'unique' ? 'UNIQUE' : '') + ' INDEX "' + index.name + '" ON "' + tableName + '" ("' + index.columns.join('","') + '")';
      }
      sqls.push(sql);
      if (!options.ignoreRelationships) {
        sqls = sqls.concat(this.createEntityRelationshipQueries(entity, force));
      }
      return sqls;
    };

    PostgreSQLStore.prototype.createEntityRelationshipQueries = function(entity, force) {
      var inversedRelationship, key, ref, reflexiveRelationship, reflexiveTableName, relationship, sqls;
      sqls = [];
      ref = entity.relationships;
      for (key in ref) {
        relationship = ref[key];
        if (relationship.toMany) {
          inversedRelationship = relationship.inverseRelationship();
          if (inversedRelationship.toMany) {
            reflexiveRelationship = this._relationshipByPriority(relationship, inversedRelationship);
            reflexiveTableName = this._getMiddleTableNameForManyToManyRelation(reflexiveRelationship);
            if (force) {
              sqls.push('DROP TABLE IF EXISTS "' + reflexiveTableName + '"');
            }
            sqls.push('CREATE TABLE IF NOT EXISTS "' + reflexiveTableName + '" ("' + reflexiveRelationship.name.toLowerCase() + '_id" serial NOT NULL,"reflexive" serial NOT NULL, PRIMARY KEY ("' + reflexiveRelationship.name.toLowerCase() + '_id","reflexive"))');
          }
        }
      }
      return sqls;
    };

    PostgreSQLStore.prototype.columnTypeForAttribute = function(attribute) {
      switch (attribute.persistentType) {
        case 'tinyint':
          return 'smallint';
        case 'mediumint':
          return 'integer';
        case 'integer':
        case 'int':
          return 'int';
        case 'timestamp':
          return 'bigint';
        case 'datetime':
        case 'date':
          return 'timestamp with time zone';
        case 'bool':
        case 'boolean':
          return 'boolean';
        case 'double':
          return 'double precision';
        case 'float':
          return 'real';
        case 'text':
          return 'text';
        case 'data':
          return 'bytea';
        default:
          return PostgreSQLStore.__super__.columnTypeForAttribute.call(this, attribute);
      }
    };

    PostgreSQLStore.prototype.encodeValueForAttribute = function(value, attribute) {
      switch (attribute.persistentType) {
        case 'boolean':
          if (value === null) {
            return null;
          }
          if (value) {
            return 'yes';
          } else {
            return 'no';
          }
      }
      return PostgreSQLStore.__super__.encodeValueForAttribute.call(this, value, attribute);
    };

    return PostgreSQLStore;

  })(GenericSQLStore);

  PostgreSQLConnection = (function(superClass) {
    extend(PostgreSQLConnection, superClass);

    function PostgreSQLConnection() {
      return PostgreSQLConnection.__super__.constructor.apply(this, arguments);
    }

    PostgreSQLConnection.prototype.connect = function(callback) {
      this.connection = new pg.Client(this.url);
      return this.connection.connect(callback);
    };

    PostgreSQLConnection.prototype.close = function() {
      return this.connection.end();
    };

    PostgreSQLConnection.prototype.execute = function(query, callback) {
      return this.connection.query(query, function(err, results) {
        return callback(err, results != null ? results.rows : void 0);
      });
    };

    PostgreSQLConnection.prototype.createRow = function(tableName, callback) {
      var query;
      query = 'INSERT INTO ' + tableName + ' ("_id") VALUES (DEFAULT) RETURNING "_id"';
      return this.connection.query(query, function(err, result) {
        if (err) {
          return callback(err);
        }
        return callback(null, result.rows[0]._id);
      });
    };

    return PostgreSQLConnection;

  })(SQLConnection);

  module.exports = PostgreSQLStore;

}).call(this);