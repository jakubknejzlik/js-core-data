var GenericPool, GenericSQLStore, ManagedObjectID, PersistentStoreRequest, PostgreSQLConnection, PostgreSQLStore, Predicate, SQLConnection, SQLTransaction, _, async, e, pg,
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

process.env.NODE_ENV = 'production';

try {
  require('pg');
} catch (error) {
  e = error;
  throw new Error('pg module is required to use SQLite storage, please install it by running npm install --save pg');
}

pg = require('pg');

if (process.env.NODE_ENV === 'production') {
  try {
    require('pg-native');
    pg = require('pg')["native"];
  } catch (error) {
    e = error;
    console.log('pg-native is recommended for running in production environment, you install module by running  npm install --save pg-native');
  }
}

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

  PostgreSQLStore.prototype.createSchemaQueries = function(options, transaction, callback) {
    var objectModel, sqls;
    if (options == null) {
      options = {};
    }
    objectModel = this.storeCoordinator.objectModel;
    sqls = [];
    return transaction.query('SELECT table_name FROM information_schema.tables WHERE table_schema = \'public\' ORDER BY table_name', (function(_this) {
      return function(err, rows) {
        var entity, i, j, key, len, len1, ref, ref1, ref2, ref3, relationship, row;
        if (err) {
          return callback(err);
        }
        for (i = 0, len = rows.length; i < len; i++) {
          row = rows[i];
          sqls.push(_this._dropTableQuery(row['table_name']));
        }
        try {
          ref = objectModel.entities;
          for (key in ref) {
            entity = ref[key];
            sqls = sqls.concat(_this.createEntityQueries(entity, options.force));
          }
          ref1 = objectModel.entities;
          for (key in ref1) {
            entity = ref1[key];
            sqls = sqls.concat(_this.createEntityRelationshipQueries(entity, options.force));
          }
          ref2 = objectModel.entities;
          for (key in ref2) {
            entity = ref2[key];
            ref3 = entity.relationships;
            for (j = 0, len1 = ref3.length; j < len1; j++) {
              relationship = ref3[j];
              if (!relationship.toMany) {
                sqls.push('ALTER TABLE "' + _this._formatTableName(entity.name) + '" ADD CONSTRAINT "fk_' + _this._formatTableName(entity.name) + '_' + relationship.name + '_id" FOREIGN KEY ("' + relationship.name + '_id")  REFERENCES "' + _this._formatTableName(relationship.destinationEntity.name) + '"("_id") ON DELETE ' + relationship.getOnDeleteRule());
              }
            }
          }
          sqls.push('CREATE TABLE IF NOT EXISTS "_meta" ("key" varchar(10) NOT NULL,"value" varchar(250) NOT NULL,PRIMARY KEY ("key"))');
          sqls.push('DELETE FROM "_meta" WHERE ' + _this.quoteSymbol + 'key' + _this.quoteSymbol + ' = \'version\'');
          sqls.push('INSERT INTO "_meta" VALUES(\'version\',\'' + objectModel.version + '\')');
          return callback(null, sqls);
        } catch (error) {
          err = error;
          return callback(err);
        }
      };
    })(this));
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
    ref = entity.getNonTransientAttributes();
    for (i = 0, len = ref.length; i < len; i++) {
      attribute = ref[i];
      columnDefinition = this._columnDefinitionForAttribute(attribute);
      if (columnDefinition) {
        parts.push(columnDefinition);
      } else {
        throw new Error('unknown attribute type ' + attribute.type);
      }
    }
    if (!options.noRelationships) {
      ref1 = entity.relationships;
      for (j = 0, len1 = ref1.length; j < len1; j++) {
        relationship = ref1[j];
        if (!relationship.toMany) {
          parts.push(this._relationshipColumnDefinition(relationship));
        }
      }
    }
    sql = 'CREATE TABLE IF NOT EXISTS "' + tableName + '" (';
    sql += parts.join(',');
    sql += ')';
    ref2 = this._indexesForEntity(entity);
    for (k = 0, len2 = ref2.length; k < len2; k++) {
      index = ref2[k];
      sql += ';CREATE ' + (index.type === 'unique' ? 'UNIQUE' : '') + ' INDEX "' + tableName + '_' + index.name + '" ON "' + tableName + '" ("' + index.columns.join('","') + '")';
    }
    sqls.push(sql);
    return sqls;
  };

  PostgreSQLStore.prototype._dropTableQuery = function(tableName) {
    return 'DROP TABLE IF EXISTS ' + this.quoteSymbol + tableName + this.quoteSymbol + ' CASCADE';
  };

  PostgreSQLStore.prototype._relationshipColumnDefinition = function(relationship) {
    return '"' + relationship.name + '_id" int DEFAULT NULL';
  };

  PostgreSQLStore.prototype._insertQueryForManyToMany = function(relationship, object, addedObject) {
    var tableName;
    tableName = this._getMiddleTableNameForManyToManyRelation(relationship);
    return 'INSERT INTO "' + tableName + '" ("reflexive","' + relationship.name + '_id") SELECT ' + this._recordIDForObjectID(object.objectID) + ',' + this._recordIDForObjectID(addedObject.objectID) + ' WHERE NOT EXISTS (SELECT 1 FROM "' + tableName + '" WHERE "reflexive" = ' + this._recordIDForObjectID(object.objectID) + ' AND "' + relationship.name + '_id" = ' + this._recordIDForObjectID(addedObject.objectID) + ')';
  };

  PostgreSQLStore.prototype._addRelationshipQueries = function(entityName, relationship) {
    return ['ALTER TABLE ' + this.quoteSymbol + this._formatTableName(entityName) + this.quoteSymbol + ' ADD COLUMN ' + this._relationshipColumnDefinition(relationship), 'ALTER TABLE "' + this._formatTableName(entityName) + '" ADD CONSTRAINT "fk_' + this._formatTableName(entityName) + '_' + relationship.name + '_id" FOREIGN KEY ("' + relationship.name + '_id")  REFERENCES "' + this._formatTableName(relationship.destinationEntity.name) + '"("_id") ON DELETE ' + relationship.getOnDeleteRule()];
  };

  PostgreSQLStore.prototype.createRelationshipQueries = function(relationship, force) {
    var inversedRelationship, parts, reflexiveRelationship, reflexiveTableName, sqls;
    sqls = [];
    if (relationship.toMany) {
      inversedRelationship = relationship.inverseRelationship();
      if (inversedRelationship.toMany) {
        reflexiveRelationship = this._relationshipByPriority(relationship, inversedRelationship);
        reflexiveTableName = this._getMiddleTableNameForManyToManyRelation(reflexiveRelationship);
        parts = [];
        parts.push('"' + reflexiveRelationship.name + '_id" serial NOT NULL');
        parts.push('"reflexive" serial NOT NULL');
        parts.push('PRIMARY KEY ("' + reflexiveRelationship.name + '_id","reflexive")');
        parts.push('CONSTRAINT "fk_' + this._formatTableName(reflexiveRelationship.entity.name) + '_' + reflexiveRelationship.name + '_id" FOREIGN KEY ("' + reflexiveRelationship.name + '_id") REFERENCES "' + this._formatTableName(reflexiveRelationship.destinationEntity.name) + '"("_id") ON DELETE CASCADE');
        parts.push('CONSTRAINT "fk_' + this._formatTableName(reflexiveRelationship.destinationEntity.name) + '_' + reflexiveRelationship.inverseRelationship().name + '" FOREIGN KEY ("reflexive") REFERENCES "' + this._formatTableName(reflexiveRelationship.entity.name) + '"("_id") ON DELETE CASCADE');
        sqls.push('CREATE TABLE IF NOT EXISTS "' + reflexiveTableName + '" (' + parts.join(',') + ')');
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
      case 'bigint':
        return 'bigint';
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
    this.connection.connect(callback);
    return this.connection.on('error', (function(_this) {
      return function(err) {
        _this.valid = false;
        return _this.log('postgres connection error', err);
      };
    })(this));
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
    query = 'INSERT INTO "' + tableName + '" ("_id") VALUES (DEFAULT) RETURNING "_id"';
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
