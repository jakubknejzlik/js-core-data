var GenericPool, GenericSQLStore, ManagedObjectID, MySQLConnection, MySQLStore, PersistentStoreRequest, Predicate, SQLConnection, String, _, async, e, mysql,
  extend = function(child, parent) { for (var key in parent) { if (hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
  hasProp = {}.hasOwnProperty;

GenericSQLStore = require('./GenericSQLStore');

PersistentStoreRequest = require('./../PersistentStoreRequest');

GenericPool = require('generic-pool');

async = require('async');

ManagedObjectID = require('./../../ManagedObjectID');

Predicate = require('./../../FetchClasses/Predicate');

String = require('string');

SQLConnection = require('./SQLConnection');

try {
  require('mysql');
} catch (error) {
  e = error;
  throw new Error('mysql module is required to use MySQL storage, please install it by running npm install --save mysql');
}

mysql = require('mysql');

_ = require('underscore');

_.mixin(require('underscore.inflections'));

MySQLStore = (function(superClass) {
  extend(MySQLStore, superClass);

  function MySQLStore() {
    return MySQLStore.__super__.constructor.apply(this, arguments);
  }

  MySQLStore.prototype.quoteSymbol = '`';

  MySQLStore.prototype.createConnection = function(url) {
    return new MySQLConnection(url, this);
  };

  MySQLStore.prototype.createSchemaQueries = function(options, transaction, callback) {
    var objectModel, sqls;
    if (options == null) {
      options = {};
    }
    objectModel = this.storeCoordinator.objectModel;
    sqls = [];
    return transaction.query('SHOW FULL TABLES WHERE TABLE_TYPE != \'VIEW\'', (function(_this) {
      return function(err, rows) {
        var i, len, row, tableNames;
        if (err) {
          return callback(err);
        }
        tableNames = [];
        for (i = 0, len = rows.length; i < len; i++) {
          row = rows[i];
          tableNames.push(row[Object.keys(row)[0]]);
        }
        return async.forEach(tableNames, function(tableName, cb) {
          var fksQuery;
          fksQuery = "SELECT CONSTRAINT_NAME as constraint_name FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE where TABLE_NAME = '" + tableName + "' AND CONSTRAINT_NAME!='PRIMARY' AND CONSTRAINT_SCHEMA='" + _this.schemaName + "' AND REFERENCED_TABLE_NAME IS NOT NULL;";
          return transaction.query(fksQuery, function(err, rows) {
            var j, len1;
            if (err) {
              return cb(err);
            }
            if (options.force) {
              for (j = 0, len1 = rows.length; j < len1; j++) {
                row = rows[j];
                sqls.push('ALTER TABLE `' + tableName + '` DROP FOREIGN KEY `' + row['constraint_name'] + '`');
              }
            }
            return cb();
          });
        }, function(err) {
          var entity, j, key, len1, ref, ref1, tableName;
          if (err) {
            return callback(err);
          }
          try {
            if (options.force) {
              for (j = 0, len1 = tableNames.length; j < len1; j++) {
                tableName = tableNames[j];
                sqls.push(_this._dropTableQuery(tableName));
              }
            }
            sqls.push('SET foreign_key_checks = 0');
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
            sqls.push('SET foreign_key_checks = 1');
            sqls.push('CREATE TABLE IF NOT EXISTS `_meta` (`key` varchar(10) NOT NULL,`value` varchar(250) NOT NULL,PRIMARY KEY (`key`)) ENGINE=InnoDB  DEFAULT CHARSET=utf8');
            sqls.push('INSERT INTO `_meta` VALUES(\'version\',\'' + objectModel.version + '\') ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)');
            return callback(null, sqls);
          } catch (error) {
            err = error;
            return callback(err);
          }
        });
      };
    })(this));
  };

  MySQLStore.prototype.createEntityQueries = function(entity, force, options) {
    var attribute, columnDefinition, i, index, j, k, len, len1, len2, parts, ref, ref1, ref2, relationship, sql, sqls, tableName;
    if (options == null) {
      options = {};
    }
    sqls = [];
    tableName = this._formatTableName(entity.name);
    parts = ['`_id` int(11) NOT NULL AUTO_INCREMENT', 'PRIMARY KEY (`_id`)'];
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
    ref1 = this._indexesForEntity(entity);
    for (j = 0, len1 = ref1.length; j < len1; j++) {
      index = ref1[j];
      parts.push((index.type === 'unique' ? 'UNIQUE ' : '') + 'KEY `' + index.name + '` (`' + index.columns.join('`,`') + '`)');
    }
    if (!options.noRelationships) {
      ref2 = entity.relationships;
      for (k = 0, len2 = ref2.length; k < len2; k++) {
        relationship = ref2[k];
        if (!relationship.toMany) {
          parts.push(this._relationshipColumnDefinition(relationship));
        }
      }
    }
    sql = 'CREATE TABLE IF NOT EXISTS `' + tableName + '` (';
    sql += parts.join(',');
    sql += ') ENGINE=InnoDB  DEFAULT CHARSET=utf8';
    sqls.push(sql);
    return sqls;
  };

  MySQLStore.prototype._foreignKeyNameForRelationship = function(relationship) {
    return 'fk_' + this._formatTableName(relationship.entity.name) + '_' + relationship.name + '_id';
  };

  MySQLStore.prototype._foreignKeyDefinitionForRelationship = function(relationship) {
    return 'CONSTRAINT `' + this._foreignKeyNameForRelationship(relationship) + '` FOREIGN KEY (`' + relationship.name + '_id`) REFERENCES `' + this._formatTableName(relationship.destinationEntity.name) + '`(`_id`) ON DELETE ' + relationship.getOnDeleteRule();
  };

  MySQLStore.prototype._renameRelationshipQuery = function(tableName, relationshipFrom, relationshipTo) {
    var sqls;
    sqls = [];
    sqls.push('ALTER TABLE ' + this.quoteSymbol + tableName + this.quoteSymbol + ' DROP FOREIGN KEY `' + this._foreignKeyNameForRelationship(relationshipFrom) + '`');
    sqls.push('ALTER TABLE ' + this.quoteSymbol + tableName + this.quoteSymbol + ' CHANGE ' + this.quoteSymbol + relationshipFrom.name + '_id' + this.quoteSymbol + ' ' + this.quoteSymbol + relationshipTo.name + '_id' + this.quoteSymbol + ' int(11) DEFAULT NULL');
    sqls.push('ALTER TABLE ' + this.quoteSymbol + tableName + this.quoteSymbol + ' ADD ' + this._foreignKeyDefinitionForRelationship(relationshipTo));
    return sqls.join(';');
  };

  MySQLStore.prototype._renameAttributeQuery = function(tableName, attributeFrom, attributeTo) {
    return 'ALTER TABLE ' + this.quoteSymbol + tableName + this.quoteSymbol + ' CHANGE ' + this.quoteSymbol + attributeFrom.name + this.quoteSymbol + ' ' + this._columnDefinitionForAttribute(attributeTo);
  };

  MySQLStore.prototype._removeRelationshipQuery = function(entityName, relationship) {
    var columnName, inverseRelationship, reflexiveRelationship, reflexiveTableName;
    inverseRelationship = relationship.inverseRelationship();
    if (relationship.toMany && inverseRelationship.toMany) {
      reflexiveRelationship = this._relationshipByPriority(relationship, inverseRelationship);
      reflexiveTableName = this._formatTableName(reflexiveRelationship.entity.name) + '_' + reflexiveRelationship.name;
      return this._dropTableQuery(reflexiveTableName);
    } else {
      columnName = relationship.name + '_id';
      return 'ALTER TABLE ' + this.quoteSymbol + this._formatTableName(entityName) + this.quoteSymbol + ' DROP FOREIGN KEY ' + this.quoteSymbol + this._foreignKeyNameForRelationship(relationship) + this.quoteSymbol + ';' + this._removeColumnQuery(entityName, columnName);
    }
  };

  MySQLStore.prototype._relationshipColumnDefinition = function(relationship) {
    return MySQLStore.__super__._relationshipColumnDefinition.call(this, relationship) + ',' + this._foreignKeyDefinitionForRelationship(relationship);
  };

  MySQLStore.prototype._addRelationshipQueries = function(entityName, relationship) {
    return ['ALTER TABLE ' + this.quoteSymbol + this._formatTableName(entityName) + this.quoteSymbol + ' ADD COLUMN ' + this.quoteSymbol + relationship.name + '_id' + this.quoteSymbol + ' int(11) DEFAULT NULL, ADD ' + this._foreignKeyDefinitionForRelationship(relationship)];
  };

  MySQLStore.prototype._insertQueryForManyToMany = function(relationship, object, addedObject) {
    return 'INSERT INTO ' + this.quoteSymbol + this._getMiddleTableNameForManyToManyRelation(relationship) + this.quoteSymbol + ' (reflexive,' + this.quoteSymbol + relationship.name + '_id' + this.quoteSymbol + ') VALUES (' + this._recordIDForObjectID(object.objectID) + ',' + this._recordIDForObjectID(addedObject.objectID) + ') ON DUPLICATE KEY UPDATE `reflexive` = VALUES(`reflexive`)';
  };

  MySQLStore.prototype.createRelationshipQueries = function(relationship, force) {
    var inversedRelationship, parts, reflexiveRelationship, reflexiveTableName, sqls;
    sqls = [];
    if (relationship.toMany) {
      inversedRelationship = relationship.inverseRelationship();
      if (inversedRelationship.toMany) {
        reflexiveRelationship = this._relationshipByPriority(relationship, inversedRelationship);
        reflexiveTableName = this._getMiddleTableNameForManyToManyRelation(reflexiveRelationship);
        if (force) {
          sqls.push('DROP TABLE IF EXISTS `' + reflexiveTableName + '`');
        }
        parts = [];
        parts.push('`' + reflexiveRelationship.name + '_id` int(11) NOT NULL');
        parts.push('`reflexive` int(11) NOT NULL');
        parts.push('PRIMARY KEY (`' + reflexiveRelationship.name + '_id`,`reflexive`)');
        parts.push('CONSTRAINT `fk_' + this._formatTableName(reflexiveRelationship.entity.name) + '_' + reflexiveRelationship.name + '_primary_id` FOREIGN KEY (`' + reflexiveRelationship.name + '_id`) REFERENCES `' + this._formatTableName(reflexiveRelationship.destinationEntity.name) + '`(`_id`) ON DELETE CASCADE');
        parts.push('CONSTRAINT `fk_' + this._formatTableName(reflexiveRelationship.destinationEntity.name) + '_' + reflexiveRelationship.inverseRelationship().name + '_reflexive_id` FOREIGN KEY (`reflexive`) REFERENCES `' + this._formatTableName(reflexiveRelationship.entity.name) + '`(`_id`) ON DELETE CASCADE');
        sqls.push('CREATE TABLE IF NOT EXISTS `' + reflexiveTableName + '` (' + parts.join(',') + ')');
      }
    }
    return sqls;
  };

  MySQLStore.prototype.columnTypeForAttribute = function(attribute) {
    var validValues;
    switch (attribute.persistentType) {
      case 'enum':
        validValues = attribute.info.values;
        if (typeof validValues === 'string') {
          validValues = validValues.split(',');
        }
        return 'ENUM(\'' + validValues.join('\',\'') + '\')';
      default:
        return MySQLStore.__super__.columnTypeForAttribute.call(this, attribute);
    }
  };

  return MySQLStore;

})(GenericSQLStore);

MySQLConnection = (function(superClass) {
  extend(MySQLConnection, superClass);

  function MySQLConnection() {
    return MySQLConnection.__super__.constructor.apply(this, arguments);
  }

  MySQLConnection.prototype.connect = function(callback) {
    var url;
    url = this.url;
    if (~url.indexOf('?')) {
      url += '&multipleStatements=yes&dateStrings=true';
    } else {
      url += '?multipleStatements=yes&dateStrings=true';
    }
    this.connection = mysql.createConnection(url);
    this.connection.connect((function(_this) {
      return function(err) {
        if (err) {
          return callback(err);
        }
        return callback(null, _this.connection);
      };
    })(this));
    return this.connection.on('error', (function(_this) {
      return function(err) {
        _this.valid = false;
        return _this.log('mysql connection error', err);
      };
    })(this));
  };

  MySQLConnection.prototype.close = function() {
    return this.connection.destroy();
  };

  MySQLConnection.prototype.execute = function(query, callback) {
    return this.connection.query(query, (function(_this) {
      return function(err, rows) {
        return callback(err, rows);
      };
    })(this));
  };

  MySQLConnection.prototype.createRow = function(tableName, callback) {
    var query;
    query = 'INSERT INTO `' + tableName + '` (`_id`) VALUES (NULL)';
    return this.execute(query, function(err, result) {
      if (err) {
        return callback(err);
      }
      return callback(null, result.insertId);
    });
  };

  return MySQLConnection;

})(SQLConnection);

module.exports = MySQLStore;
