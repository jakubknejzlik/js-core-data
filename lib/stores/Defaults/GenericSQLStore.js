var FetchRequest, GenericSQLStore, IncrementalStore, ManagedObjectContext, ManagedObjectID, PersistentStoreCoordinator, PersistentStoreRequest, Predicate, Promise, SQLConnectionPool, SortDescriptor, _, async, moment, squel, url,
  extend = function(child, parent) { for (var key in parent) { if (hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; },
  hasProp = {}.hasOwnProperty,
  indexOf = [].indexOf || function(item) { for (var i = 0, l = this.length; i < l; i++) { if (i in this && this[i] === item) return i; } return -1; };

url = require('url');

async = require('async');

squel = require('squel');

moment = require('moment');

Promise = require('bluebird');

IncrementalStore = require('./../IncrementalStore');

PersistentStoreRequest = require('./../PersistentStoreRequest');

ManagedObjectID = require('./../../ManagedObjectID');

Predicate = require('./../../FetchClasses/Predicate');

FetchRequest = require('./../../FetchRequest');

SortDescriptor = require('./../../FetchClasses/SortDescriptor');

PersistentStoreCoordinator = require('../../PersistentStoreCoordinator');

ManagedObjectContext = require('../../ManagedObjectContext');

SQLConnectionPool = require('./SQLConnectionPool');

_ = require('underscore');

_.mixin(require('underscore.inflections'));

GenericSQLStore = (function(superClass) {
  extend(GenericSQLStore, superClass);

  GenericSQLStore.prototype.tableAlias = 'SELF';

  GenericSQLStore.prototype.quoteSymbol = '"';

  function GenericSQLStore(storeCoordinator, URL, globals) {
    var parsedUrl;
    this.storeCoordinator = storeCoordinator;
    this.URL = URL;
    this.globals = globals;
    parsedUrl = url.parse(this.URL);
    this.schemaName = parsedUrl.pathname.substring(1);
    this.auth = parsedUrl.auth;
    if (this.storeCoordinator) {
      this.connectionPool = new SQLConnectionPool(this.URL, (function(_this) {
        return function(url) {
          return _this.createConnection(url);
        };
      })(this), this, this.globals);
    }
    this.permanentIDsCache = {};
  }

  GenericSQLStore.prototype.createConnection = function(url) {
    throw new Error('createConnection must be overriden');
  };

  GenericSQLStore.prototype.closeAllConnections = function(callback) {
    return this.connectionPool.closeAllConnections(callback);
  };

  GenericSQLStore.prototype.execute = function(request, context, callback, afterInsertCallback) {
    if (!(request instanceof PersistentStoreRequest)) {
      throw new Error('request ' + request + ' is not instance of PersistentStoreRequest');
    }
    if (request.type === 'save') {
      this.connectionPool.createTransaction((function(_this) {
        return function(err, transaction) {
          if (err) {
            return callback(err);
          }
          return async.series([
            function(seriesCallback) {
              return async.forEach(request.insertedObjects, function(insertedObject, cb) {
                var formattedTableName;
                formattedTableName = _this._formatTableName(insertedObject.entity.name);
                return transaction.createRow(formattedTableName, function(err, rowId) {
                  if (err) {
                    return cb(err);
                  }
                  _this.permanentIDsCache[insertedObject.objectID.toString()] = rowId;
                  return cb();
                });
              }, function(err) {
                afterInsertCallback();
                return seriesCallback(err);
              });
            }, function(seriesCallback) {
              return async.forEach(request.deletedObjects, function(deletedObject, cb) {
                var formattedTableName, id, sql;
                formattedTableName = _this._formatTableName(deletedObject.entity.name);
                id = _this._recordIDForObjectID(deletedObject.objectID);
                sql = 'DELETE FROM ' + _this.quoteSymbol + formattedTableName + _this.quoteSymbol + ' WHERE ' + _this.quoteSymbol + '_id' + _this.quoteSymbol + ' = ' + id;
                return transaction.query(sql, function(err) {
                  return cb(err);
                });
              }, seriesCallback);
            }, function(seriesCallback) {
              return async.forEachSeries(request.insertedObjects, function(insertedObject, cb) {
                var ref, sql, updateValues;
                ref = _this.updateQueryForUpdatedObject(insertedObject), sql = ref[0], updateValues = ref[1];
                if (sql) {
                  return transaction.query(sql, updateValues, cb);
                } else {
                  return cb();
                }
              }, seriesCallback);
            }, function(seriesCallback) {
              return async.forEachSeries(request.insertedObjects, function(insertedObject, cb) {
                return _this._updateRelationsForObject(transaction, insertedObject, cb);
              }, seriesCallback);
            }, function(seriesCallback) {
              return async.forEachSeries(request.updatedObjects, function(updatedObject, cb) {
                var ref, sql, updateValues;
                ref = _this.updateQueryForUpdatedObject(updatedObject), sql = ref[0], updateValues = ref[1];
                if (sql) {
                  return transaction.query(sql, updateValues, cb);
                } else {
                  return cb();
                }
              }, seriesCallback);
            }, function(seriesCallback) {
              return async.forEachSeries(request.updatedObjects, function(updatedObject, cb) {
                return _this._updateRelationsForObject(transaction, updatedObject, cb);
              }, seriesCallback);
            }
          ], function(err) {
            if (err) {
              return transaction.rollback(function() {
                _this.connectionPool.releaseTransaction(transaction);
                return callback(err);
              });
            }
            return transaction.commit(function(err) {
              _this.connectionPool.releaseTransaction(transaction);
              return callback(err);
            });
          });
        };
      })(this));
    }
    if (request.type === 'fetch') {
      return this.connectionPool.query(this.sqlForFetchRequest(request), (function(_this) {
        return function(err, rows) {
          var _row, attribute, columnName, ids, j, k, l, len, len1, len2, len3, m, objectID, objectValues, ref, ref1, ref2, relationship, row;
          ids = [];
          if (err) {
            return callback(err);
          }
          if (request.resultType === FetchRequest.RESULT_TYPE.VALUES) {
            return callback(null, rows);
          }
          objectValues = {};
          for (j = 0, len = rows.length; j < len; j++) {
            row = rows[j];
            _row = {};
            ref = request.entity.getNonTransientAttributes();
            for (k = 0, len1 = ref.length; k < len1; k++) {
              attribute = ref[k];
              _row[attribute.name] = row[attribute.name];
            }
            ref1 = request.entity.relationships;
            for (l = 0, len2 = ref1.length; l < len2; l++) {
              relationship = ref1[l];
              if (!relationship.toMany) {
                columnName = _.singularize(relationship.name) + '_id';
                _row[columnName] = row[columnName];
              }
            }
            objectID = _this._permanentIDForRecord(request.entity, row._id);
            ref2 = request.entity.getNonTransientAttributes();
            for (m = 0, len3 = ref2.length; m < len3; m++) {
              attribute = ref2[m];
              _row[attribute.name] = _this.decodeValueForAttribute(_row[attribute.name], attribute);
            }
            objectValues[objectID.toString()] = _row;
            ids.push(objectID);
          }
          return callback(null, ids, objectValues);
        };
      })(this));
    }
  };

  GenericSQLStore.prototype.numberOfObjectsForFetchRequest = function(request, callback) {
    return this.connectionPool.query(this.countSqlForFetchRequest(request), (function(_this) {
      return function(err, result) {
        var ref;
        return callback(err, Number(result != null ? (ref = result[0]) != null ? ref.count : void 0 : void 0));
      };
    })(this));
  };

  GenericSQLStore.prototype.updateQueryForUpdatedObject = function(updatedObject) {
    var attribute, e, formattedTableName, id, key, updateValues, updates, value, values;
    formattedTableName = this._formatTableName(updatedObject.entity.name);
    id = this._recordIDForObjectID(updatedObject.objectID);
    values = this._valuesWithRelationshipsForObject(updatedObject);
    updates = [];
    updateValues = [];
    for (key in values) {
      value = values[key];
      try {
        attribute = updatedObject.entity.getAttribute(key);
      } catch (error) {
        e = error;
        attribute = null;
      }
      if (attribute) {
        updates.push(this.quoteSymbol + key + this.quoteSymbol + ' = ?');
        updateValues.push(this.encodeValueForAttribute(attribute.encode(value), attribute));
      } else {
        updates.push(this.quoteSymbol + key + this.quoteSymbol + ' = ?');
        updateValues.push(value);
      }
    }
    if (updates.length > 0) {
      return ['UPDATE ' + this.quoteSymbol + formattedTableName + this.quoteSymbol + ' SET ' + updates.join(',') + ' WHERE ' + this.quoteSymbol + '_id' + this.quoteSymbol + ' = ' + id, updateValues];
    } else {
      return [null, null];
    }
  };

  GenericSQLStore.prototype.processRequest = function(request) {
    var allFieldsMark, attribute, field, fields, j, k, len, len1, name, ref, ref1, ref2;
    if (!request.fields) {
      fields = {};
      ref = request.entity.getNonTransientAttributes();
      for (j = 0, len = ref.length; j < len; j++) {
        attribute = ref[j];
        fields[attribute.name] = this.tableAlias + '.' + attribute.name;
      }
      request.fields = fields;
      request.fields['_id'] = this.tableAlias + '._id';
    } else {
      allFieldsMark = null;
      ref1 = request.fields;
      for (name in ref1) {
        field = ref1[name];
        if (field === 'SELF.*' || field === '*') {
          allFieldsMark = name;
          break;
        }
      }
      if (allFieldsMark) {
        delete request.fields[allFieldsMark];
        ref2 = request.entity.getNonTransientAttributes();
        for (k = 0, len1 = ref2.length; k < len1; k++) {
          attribute = ref2[k];
          request.fields[attribute.name] = this.tableAlias + '.' + attribute.name;
        }
        request.fields['_id'] = this.tableAlias + '._id';
      }
    }
    if (request.type !== 'fetch') {
      return request.fields['_id'] = this.tableAlias + '._id';
    }
  };

  GenericSQLStore.prototype.countSqlForFetchRequest = function(request) {
    var query, sqlString;
    this.processRequest(request);
    query = squel.select({
      autoQuoteAliasNames: false
    }).from(this._formatTableName(request.entity.name), this.tableAlias);
    query.field('COUNT(DISTINCT ' + this.tableAlias + '._id)', 'count');
    if (request.predicate) {
      query.where(this.parsePredicate(request.predicate), request);
    }
    if (request.havingPredicate) {
      query.having(this.parsePredicate(request.havingPredicate, request));
    }
    if (request.group) {
      query.group(request.group);
    }
    sqlString = this._getRawTranslatedQueryWithJoins(query, request);
    return this.processQuery(sqlString, request);
  };

  GenericSQLStore.prototype.sqlForFetchRequest = function(request) {
    var attribute, column, columnName, descriptor, descriptors, field, j, k, l, len, len1, len2, name, query, ref, ref1, ref2, relationship, sqlString;
    query = squel.select({
      autoQuoteAliasNames: false
    }).from(this._formatTableName(request.entity.name), this.tableAlias);
    if (request.resultType === FetchRequest.RESULT_TYPE.MANAGED_OBJECTS) {
      query.group(this.tableAlias + '._id');
      query.field(this.tableAlias + '.' + this.quoteSymbol + '_id' + this.quoteSymbol, this.quoteSymbol + '_id' + this.quoteSymbol);
      ref = request.entity.getNonTransientAttributes();
      for (j = 0, len = ref.length; j < len; j++) {
        attribute = ref[j];
        query.field(this.tableAlias + '.' + this.quoteSymbol + attribute.name + this.quoteSymbol, this.quoteSymbol + attribute.name + this.quoteSymbol);
      }
      ref1 = request.entity.relationships;
      for (k = 0, len1 = ref1.length; k < len1; k++) {
        relationship = ref1[k];
        if (!relationship.toMany) {
          columnName = _.singularize(relationship.name) + '_id';
          query.field(this.tableAlias + '.' + this.quoteSymbol + columnName + this.quoteSymbol, this.quoteSymbol + columnName + this.quoteSymbol);
        }
      }
    } else {
      this.processRequest(request);
      ref2 = request.fields;
      for (name in ref2) {
        field = ref2[name];
        query.field(field, this.quoteSymbol + name + this.quoteSymbol);
      }
      if (request.group) {
        query.group(request.group);
      }
    }
    if (request.predicate) {
      query.where(this.parsePredicate(request.predicate, request));
    }
    if (request.havingPredicate) {
      query.having(this.parsePredicate(request.havingPredicate, request));
    }
    if (request.limit) {
      query.limit(request.limit);
    }
    if (request.offset) {
      query.offset(request.offset);
    }
    if (Array.isArray(request.sortDescriptors) && request.sortDescriptors.length > 0) {
      descriptors = request.sortDescriptors;
      for (l = 0, len2 = descriptors.length; l < len2; l++) {
        descriptor = descriptors[l];
        column = descriptor.attribute;
        if (column.indexOf(this.tableAlias + '.') === -1) {
          column = this.tableAlias + '.' + column;
        }
        query.order(column, descriptor.ascending);
      }
    }
    sqlString = this._getRawTranslatedQueryWithJoins(query, request);
    return this.processQuery(sqlString, request);
  };

  GenericSQLStore.prototype.parsePredicate = function(predicate, request) {
    var string;
    string = predicate.toString();
    return string;
  };

  GenericSQLStore.prototype._getRawTranslatedQueryWithJoins = function(query, request) {
    var _subkeys, alreadyJoined, clearedSQLString, fieldName, fieldValue, i, j, joinMatches, joins, key, leftJoin, len, match, ref, ref1, replaceNameSorted, replaceNames, sqlString;
    replaceNames = {};
    joins = {};
    sqlString = query.toString();
    if (request != null ? request.fields : void 0) {
      ref = request.fields;
      for (fieldName in ref) {
        fieldValue = ref[fieldName];
        if (fieldValue.indexOf(this.tableAlias + '.' + fieldName) === -1) {
          sqlString = sqlString.replace(new RegExp(this.tableAlias + '.' + fieldName, 'g'), fieldValue);
        }
      }
    }
    clearedSQLString = sqlString.replace(/\\"/g, '').replace(/"[^"]+"/g, '').replace(/\\'/g, '').replace(/'[^']+'/g, '');
    joinMatches = clearedSQLString.match(new RegExp(this.tableAlias + '(\\.[a-zA-Z_"][a-zA-Z0-9_"]*){2,}', 'g'));
    if (!joinMatches || joinMatches.length === 0) {
      return sqlString;
    }
    leftJoin = (function(_this) {
      return function(subkeys, parentEntity, path) {
        var as, inversedRelation, middleTableName, middleTableNameAlias, parentAlias, pathAlias, primaryRelation, relation, subPath;
        as = subkeys.shift();
        relation = parentEntity.getRelationship(as);
        if (!relation) {
          throw new Error('relation ' + parentEntity.name + '=>' + as + ' not found');
        }
        inversedRelation = relation.inverseRelationship();
        subPath = path + "." + as;
        if (!~alreadyJoined.indexOf(subPath)) {
          alreadyJoined.push(subPath);
          if (!replaceNames[path]) {
            replaceNames[path] = path.replace(/\./g, "_");
          }
          if (!replaceNames[subPath]) {
            replaceNames[subPath] = subPath.replace(/\./g, "_");
          }
          parentAlias = replaceNames[path];
          pathAlias = replaceNames[subPath];
          if (relation.toMany && inversedRelation.toMany) {
            primaryRelation = _this._relationshipByPriority(relation, inversedRelation);
            inversedRelation = relation.inverseRelationship();
            middleTableName = _this._getMiddleTableNameForManyToManyRelation(primaryRelation);
            middleTableNameAlias = pathAlias + "__mid";
            if (primaryRelation === relation) {
              query.left_join(_this.quoteSymbol + middleTableName + _this.quoteSymbol, middleTableNameAlias, parentAlias + "._id = " + middleTableNameAlias + ".reflexive");
              query.left_join(_this.quoteSymbol + _this._formatTableName(relation.destinationEntity.name) + _this.quoteSymbol, pathAlias, middleTableNameAlias + "." + relation.name + "_id = " + pathAlias + "._id");
            } else {
              query.left_join(_this.quoteSymbol + middleTableName + _this.quoteSymbol, middleTableNameAlias, parentAlias + "._id = " + middleTableNameAlias + "." + inversedRelation.name + "_id");
              query.left_join(_this.quoteSymbol + _this._formatTableName(relation.destinationEntity.name) + _this.quoteSymbol, pathAlias, middleTableNameAlias + ".reflexive" + " = " + pathAlias + "._id");
            }
          } else {
            if (relation.toMany) {
              query.left_join(_this.quoteSymbol + _this._formatTableName(relation.destinationEntity.name) + _this.quoteSymbol, pathAlias, pathAlias + "." + _.singularize(inversedRelation.name) + "_id" + " = " + parentAlias + "._id");
            } else {
              query.left_join(_this.quoteSymbol + _this._formatTableName(relation.destinationEntity.name) + _this.quoteSymbol, pathAlias, pathAlias + '._id' + ' = ' + parentAlias + '.' + relation.name + '_id');
            }
          }
        }
        if (subkeys.length > 0) {
          return leftJoin(subkeys, relation.destinationEntity, subPath);
        }
      };
    })(this);
    replaceNames[this.tableAlias] = this.tableAlias;
    for (j = 0, len = joinMatches.length; j < len; j++) {
      match = joinMatches[j];
      match = match.slice(0, match.lastIndexOf("."));
      if (match !== this.tableAlias) {
        replaceNames[match] = match.replace(/\./g, "_");
        match = match.replace(this.tableAlias + ".", "");
        joins[match] = match;
      }
    }
    alreadyJoined = [];
    for (key in joins) {
      _subkeys = key.split(".");
      leftJoin(_subkeys, request.entity, this.tableAlias);
    }
    replaceNameSorted = Object.keys(replaceNames).sort().reverse();
    sqlString = query.toString();
    if (request != null ? request.fields : void 0) {
      ref1 = request.fields;
      for (fieldName in ref1) {
        fieldValue = ref1[fieldName];
        if (fieldValue.indexOf(this.tableAlias + '.' + fieldName) === -1) {
          sqlString = sqlString.replace(new RegExp(this.tableAlias + '.' + fieldName, 'g'), fieldValue);
        }
      }
    }
    for (i in replaceNameSorted) {
      sqlString = sqlString.replace(new RegExp(replaceNameSorted[i].replace(".", "\\.") + "\\.(?![^\\s_]+\\\")", "g"), replaceNames[replaceNameSorted[i]] + ".");
      sqlString = sqlString.replace(new RegExp(replaceNameSorted[i].replace(".", "\\.") + this.quoteSymbol, "g"), replaceNames[replaceNameSorted[i]] + this.quoteSymbol);
    }
    return sqlString;
  };

  GenericSQLStore.prototype.processQuery = function(query, request) {
    var column, columnAfter, columnRegExp, j, len, match, matches, regString, tableName;
    regString = query.replace(new RegExp('\'[^\']+\'', 'g'), '\'ignored\'');
    columnRegExp = new RegExp(this.tableAlias + '[\\w_]*(\\.[\\w_]+)+', 'gi');
    matches = regString.match(columnRegExp);
    matches = _.unique(matches);
    matches.sort().reverse();
    if (matches) {
      for (j = 0, len = matches.length; j < len; j++) {
        match = matches[j];
        column = match.replace(/\./g, '\.');
        columnAfter = match.replace(/\.([^\.]+)$/g, '.' + this.quoteSymbol + '$1' + this.quoteSymbol);
        query = query.replace(new RegExp(column, 'g'), columnAfter);
      }
    }
    tableName = this._formatTableName(request.entity.name);
    query = query.replace("FROM " + tableName + " " + this.tableAlias, "FROM " + this.quoteSymbol + tableName + this.quoteSymbol + " " + this.tableAlias);
    return query;
  };

  GenericSQLStore.prototype._updateRelationsForObject = function(transaction, object, callback) {
    var addedObject, addedObjects, inversedRelationship, j, k, l, len, len1, len2, ref, ref1, ref2, reflexiveRelationship, relationship, removedObject, removedObjects, sql, sqls;
    sqls = [];
    ref = object.entity.relationships;
    for (j = 0, len = ref.length; j < len; j++) {
      relationship = ref[j];
      inversedRelationship = relationship.inverseRelationship();
      reflexiveRelationship = this._relationshipByPriority(relationship, inversedRelationship);
      if (relationship.toMany && inversedRelationship.toMany && object._relationChanges && relationship === reflexiveRelationship) {
        addedObjects = (ref1 = object._relationChanges) != null ? ref1['added_' + relationship.name] : void 0;
        if (addedObjects) {
          for (k = 0, len1 = addedObjects.length; k < len1; k++) {
            addedObject = addedObjects[k];
            sqls.push(this._insertQueryForManyToMany(relationship, object, addedObject));
          }
        }
        removedObjects = (ref2 = object._relationChanges) != null ? ref2['removed_' + relationship.name] : void 0;
        if (removedObjects) {
          for (l = 0, len2 = removedObjects.length; l < len2; l++) {
            removedObject = removedObjects[l];
            sql = 'DELETE FROM ' + this.quoteSymbol + this._getMiddleTableNameForManyToManyRelation(relationship) + this.quoteSymbol + ' WHERE reflexive = ' + this._recordIDForObjectID(object.objectID) + ' AND ' + this.quoteSymbol + relationship.name + '_id' + this.quoteSymbol + ' = ' + this._recordIDForObjectID(removedObject.objectID);
            sqls.push(sql);
          }
        }
      }
    }
    return async.forEachSeries(sqls, function(sql, cb) {
      return transaction.query(sql, cb);
    }, callback);
  };

  GenericSQLStore.prototype._insertQueryForManyToMany = function(relationship, object, addedObject) {
    return 'INSERT INTO ' + this.quoteSymbol + this._getMiddleTableNameForManyToManyRelation(relationship) + this.quoteSymbol + ' (reflexive,' + this.quoteSymbol + relationship.name + '_id' + this.quoteSymbol + ') VALUES (' + this._recordIDForObjectID(object.objectID) + ',' + this._recordIDForObjectID(addedObject.objectID) + ')';
  };

  GenericSQLStore.prototype._getMiddleTableNameForManyToManyRelation = function(relationship) {
    var inversedRelationship, reflexiveRelationship;
    inversedRelationship = relationship.inverseRelationship();
    reflexiveRelationship = this._relationshipByPriority(relationship, inversedRelationship);
    return this._formatTableName(reflexiveRelationship.entity.name) + '_' + reflexiveRelationship.name.toLowerCase();
  };

  GenericSQLStore.prototype._valuesWithRelationshipsForObject = function(object) {
    var data, id, j, key, len, ref, ref1, ref2, ref3, relation, value;
    data = {};
    ref = object._changes;
    for (key in ref) {
      value = ref[key];
      data[key] = value;
    }
    ref1 = object.entity.relationships;
    for (j = 0, len = ref1.length; j < len; j++) {
      relation = ref1[j];
      if (!relation.toMany) {
        if (((ref2 = object._relationChanges) != null ? ref2[relation.name] : void 0) !== void 0) {
          if ((ref3 = object._relationChanges) != null ? ref3[relation.name] : void 0) {
            id = this._recordIDForObjectID(object._relationChanges[relation.name].objectID);
            data[relation.name + '_id'] = id;
          } else {
            data[relation.name + '_id'] = null;
          }
        }
      }
    }
    return data;
  };

  GenericSQLStore.prototype.permanentIDsForObjects = function(objects) {
    var ids, j, len, object;
    ids = [];
    for (j = 0, len = objects.length; j < len; j++) {
      object = objects[j];
      ids.push(this._permanentIDForRecord(object.entity, this.permanentIDsCache[object.objectID.toString()]));
    }
    return ids;
  };

  GenericSQLStore.prototype.newObjectID = function(entity, referenceObject) {
    return new ManagedObjectID(this.URL + '/' + entity.name + '/t' + referenceObject, entity);
  };

  GenericSQLStore.prototype._permanentIDForRecord = function(entity, referenceObject) {
    return new ManagedObjectID(this.URL + '/' + entity.name + '/p' + referenceObject, entity);
  };

  GenericSQLStore.prototype._recordIDForObjectID = function(objectID) {
    return objectID.recordId();
  };

  GenericSQLStore.prototype._relationshipByPriority = function(relationship, inversedRelationship) {
    if (relationship.name > inversedRelationship.name) {
      return relationship;
    }
    return inversedRelationship;
  };

  GenericSQLStore.prototype._formatTableName = function(name) {
    return _.pluralize(name).toLowerCase();
  };

  GenericSQLStore.prototype.columnTypeForAttribute = function(attribute) {
    var type;
    type = null;
    switch (attribute.persistentType) {
      case 'bool':
      case 'boolean':
        type = 'tinyint(1)';
        break;
      case 'string':
      case 'email':
      case 'url':
        type = 'varchar(' + (attribute.info.length || 255) + ')';
        break;
      case 'text':
        if (attribute.info.length) {
          if (attribute.info.length < 256) {
            type = 'tinytext';
          } else if (attribute.info.length < 65536) {
            type = 'text';
          } else if (attribute.info.length < 16777216) {
            type = 'mediumtext';
          } else if (attribute.info.length < 4294967296) {
            type = 'longtext';
          }
        } else {
          type = 'longtext';
        }
        break;
      case 'data':
        if (attribute.info.length) {
          if (attribute.info.length < 256) {
            type = 'tinyblob';
          } else if (attribute.info.length < 65536) {
            type = 'blob';
          } else if (attribute.info.length < 16777216) {
            type = 'mediumblob';
          } else if (attribute.info.length < 4294967296) {
            type = 'longblob';
          }
        } else {
          type = 'longblob';
        }
        break;
      case 'int':
      case 'integer':
        type = 'int(' + (attribute.info.length || 11) + ')';
        break;
      case 'bigint':
        type = 'bigint(' + (attribute.info.length || 20) + ')';
        break;
      case 'decimal':
        type = 'decimal(' + (attribute.info.digits || 20) + ',' + (attribute.info.decimals || 5) + ')';
        break;
      case 'float':
        type = 'float';
        break;
      case 'double':
        type = 'double';
        break;
      case 'date':
        type = 'datetime';
        break;
      case 'timestamp':
        type = 'bigint(20)';
        break;
      case 'uuid':
        type = 'char(36)';
        break;
      case 'transformable':
        type = 'mediumtext';
        break;
      case 'enum':
        return 'varchar(' + (attribute.info.length || 30) + ')';
      default:
        return null;
    }
    return type;
  };

  GenericSQLStore.prototype._columnDefinitionForAttribute = function(attribute) {
    var definition, type;
    type = this.columnTypeForAttribute(attribute);
    if (!type) {
      return null;
    }
    definition = this.quoteSymbol + attribute.name + this.quoteSymbol + ' ' + type + ' DEFAULT NULL';
    if (attribute.info.unique) {
      definition += ' UNIQUE';
    }
    return definition;
  };

  GenericSQLStore.prototype.encodeValueForAttribute = function(value, attribute) {
    if (value === null) {
      return null;
    }
    switch (attribute.persistentType) {
      case 'datetime':
      case 'date':
        return moment.utc(value).toISOString();
    }
    return value;
  };

  GenericSQLStore.prototype.decodeValueForAttribute = function(value, attribute) {
    if (value === null) {
      return null;
    }
    switch (attribute.persistentType) {
      case 'datetime':
      case 'date':
        return moment.utc(value).toDate();
      case 'timestamp':
        return Number(value);
      case 'boolean':
        return !!value;
    }
    return value;
  };

  GenericSQLStore.prototype._indexesForEntity = function(entity) {
    var attribute, indexes, j, len, ref;
    indexes = _.clone(entity.indexes);
    ref = entity.getNonTransientAttributes();
    for (j = 0, len = ref.length; j < len; j++) {
      attribute = ref[j];
      if (attribute.info.indexed) {
        indexes.push({
          name: attribute.name,
          columns: [attribute.name],
          type: 'key'
        });
      }
    }
    return indexes;
  };

  GenericSQLStore.prototype.syncSchema = function(options) {
    return new Promise((function(_this) {
      return function(resolve, reject) {
        return _this.connectionPool.createTransaction(function(err, transaction) {
          if (err) {
            return reject(err);
          }
          return _this.createSchemaQueries(options, transaction, function(err, queries) {
            if (err) {
              return transaction.rollback(function() {
                return reject(err);
              });
            } else {
              return _this._runRawQueriesInSingleTransaction(queries, transaction, function(err, result) {
                if (err) {
                  return reject(err);
                }
                return resolve(result);
              });
            }
          });
        });
      };
    })(this));
  };

  GenericSQLStore.prototype.runMigration = function(migration) {
    return new Promise((function(_this) {
      return function(resolve, reject) {
        var objectModel;
        objectModel = _this.storeCoordinator.objectModel;
        return async.forEachSeries(migration.scriptsBefore, function(script, cb) {
          return _this._runMigrationScript(migration.modelFrom, script, cb);
        }, function(err) {
          var queries;
          if (err) {
            return reject(err);
          }
          try {
            queries = _this.createMigrationQueries(migration);
            queries.push('UPDATE ' + _this.quoteSymbol + '_meta' + _this.quoteSymbol + ' SET ' + _this.quoteSymbol + 'value' + _this.quoteSymbol + ' = \'' + objectModel.version + '\' WHERE ' + _this.quoteSymbol + 'key' + _this.quoteSymbol + ' = \'version\'');
          } catch (error) {
            err = error;
            return reject(err);
          }
          return _this._runRawQueriesInSingleTransaction(queries, function(err) {
            if (err) {
              return reject(err);
            }
            return async.forEachSeries(migration.scriptsAfter, function(script, cb) {
              return _this._runMigrationScript(migration.modelTo, script, cb);
            }, function(err, result) {
              if (err) {
                return reject(err);
              }
              return resolve(result);
            });
          });
        });
      };
    })(this));
  };

  GenericSQLStore.prototype._runMigrationScript = function(model, script, callback) {
    var context, err, persistentStoreCoordinator;
    persistentStoreCoordinator = new PersistentStoreCoordinator(model, this.storeCoordinator.globals);
    persistentStoreCoordinator.addStore(this);
    context = new ManagedObjectContext(persistentStoreCoordinator);
    try {
      return script.script(context, (function(_this) {
        return function(err) {
          if (err) {
            context.destroy();
            return callback(err);
          }
          return context.saveAndDestroy(callback);
        };
      })(this));
    } catch (error) {
      err = error;
      return callback(new Error('error running script on model ' + model.version + ', script name: \'' + (script.name || 'unknown') + '\', error: \'' + err.message + '\''));
    }
  };

  GenericSQLStore.prototype.getCurrentVersion = function() {
    return new Promise((function(_this) {
      return function(resolve, reject) {
        var query;
        query = squel.select().from('_meta').field('value').where(_this.quoteSymbol + 'key' + _this.quoteSymbol + ' = ?', 'version').limit(1);
        return _this.connectionPool.query(query.toString(), function(err, rows) {
          var ref;
          if (!rows) {
            return resolve(null);
          }
          return resolve((ref = rows[0]) != null ? ref.value : void 0);
        });
      };
    })(this));
  };

  GenericSQLStore.prototype.createMigrationQueries = function(migration) {
    var addedEntitiesNames, attribute, change, changedRelationshipsSqls, e, entity, entityChangedNames, entityFrom, entityName, entityTo, inverseRelationship, j, k, l, len, len1, len10, len11, len12, len2, len3, len4, len5, len6, len7, len8, len9, m, modelFrom, modelTo, n, name, newAttribute, newInverseRelationship, newReflexiveRelationship, newReflexiveTableName, newRelationship, o, p, q, r, ref, ref1, ref10, ref11, ref12, ref13, ref14, ref15, ref16, ref17, ref18, ref19, ref2, ref20, ref21, ref22, ref23, ref24, ref25, ref26, ref27, ref3, ref4, ref5, ref6, ref7, ref8, ref9, reflexiveRelationship, reflexiveTableName, relationship, s, sqls, t, u, updatedEntities, v;
    sqls = [];
    changedRelationshipsSqls = [];
    entityChangedNames = {};
    addedEntitiesNames = [];
    modelTo = migration.modelTo;
    modelFrom = migration.modelFrom;
    ref = migration.entitiesChanges;
    for (j = 0, len = ref.length; j < len; j++) {
      change = ref[j];
      entityName = change.entity;
      switch (change.change) {
        case '+':
          addedEntitiesNames.push(entityName);
          sqls = sqls.concat(this.createEntityQueries(modelTo.getEntity(entityName), false, {
            noRelationships: true
          }));
          ref1 = modelTo.getEntity(entityName).relationships;
          for (k = 0, len1 = ref1.length; k < len1; k++) {
            relationship = ref1[k];
            inverseRelationship = relationship.inverseRelationship();
            if (!relationship.toMany) {
              changedRelationshipsSqls = changedRelationshipsSqls.concat(this._addRelationshipQueries(relationship.entity.name, relationship));
            }
            if (!inverseRelationship.toMany) {
              changedRelationshipsSqls = changedRelationshipsSqls.concat(this._addRelationshipQueries(inverseRelationship.entity.name, inverseRelationship));
            }
          }
          break;
        case '-':
          entity = modelFrom.getEntity(entityName);
          ref2 = entity.relationshipsByName();
          for (name in ref2) {
            relationship = ref2[name];
            sqls.push(this._removeRelationshipQuery(entityName, relationship));
          }
          sqls = sqls.concat(this._dropEntityQueries(modelFrom.getEntity(entityName)));
          break;
        default:
          entityChangedNames[change.change] = entityName;
          sqls.push('ALTER TABLE ' + this.quoteSymbol + this._formatTableName(entityName) + this.quoteSymbol + ' RENAME TO ' + this.quoteSymbol + this._formatTableName(change.change) + this.quoteSymbol);
      }
    }
    ref3 = migration.entitiesChanges;
    for (l = 0, len2 = ref3.length; l < len2; l++) {
      change = ref3[l];
      entityName = change.entity;
      switch (change.change) {
        case '+':
          ref4 = modelTo.getEntity(entityName).relationships;
          for (m = 0, len3 = ref4.length; m < len3; m++) {
            relationship = ref4[m];
            inverseRelationship = relationship.inverseRelationship();
            if (relationship.toMany && inverseRelationship.toMany) {
              sqls = sqls.concat(this.createRelationshipQueries(relationship));
            }
          }
      }
    }
    updatedEntities = _.uniq(Object.keys(migration.attributesChanges).concat(Object.keys(migration.relationshipsChanges)));
    for (n = 0, len4 = updatedEntities.length; n < len4; n++) {
      entityName = updatedEntities[n];
      entityTo = modelTo.getEntity(entityName) || modelTo.getEntity(entityChangedNames[entityName]);
      entityFrom = modelFrom.getEntity(entityName) || modelFrom.getEntity(entityChangedNames[entityName]);
      if (entityFrom) {
        ref5 = entityFrom.getNonTransientAttributes();
        for (o = 0, len5 = ref5.length; o < len5; o++) {
          attribute = ref5[o];
          change = (ref6 = migration.attributesChanges[entityName]) != null ? ref6[attribute.name] : void 0;
          if (change) {
            switch (change) {
              case '+':
                break;
              case '-':
                sqls.push(this._removeColumnQuery(entityName, attribute.name));
                break;
              default:
                try {
                  newAttribute = entityTo.getAttribute(change);
                  sqls.push(this._renameAttributeQuery(this._formatTableName(entityName), attribute, newAttribute));
                } catch (error) {
                  e = error;
                  throw new Error('attribute ' + entityTo.name + '->' + change + ' not found in version ' + modelFrom.version);
                }
            }
          }
        }
      }
      if (entityTo && indexOf.call(addedEntitiesNames, entityName) < 0) {
        ref7 = entityTo.getNonTransientAttributes();
        for (p = 0, len6 = ref7.length; p < len6; p++) {
          attribute = ref7[p];
          change = (ref8 = migration.attributesChanges[entityName]) != null ? ref8[attribute.name] : void 0;
          if (change === '+') {
            sqls.push('ALTER TABLE ' + this.quoteSymbol + this._formatTableName(entityName) + this.quoteSymbol + ' ADD COLUMN ' + this._columnDefinitionForAttribute(attribute));
          }
        }
      }
      if (entityFrom) {
        ref9 = entityFrom.relationships;
        for (q = 0, len7 = ref9.length; q < len7; q++) {
          relationship = ref9[q];
          if (!relationship.toMany) {
            change = (ref10 = migration.relationshipsChanges[entityName]) != null ? ref10[relationship.name] : void 0;
            if (change && (change !== '+' && change !== '-')) {
              try {
                newRelationship = entityTo.getRelationship(change);
                sqls.push(this._renameRelationshipQuery(this._formatTableName(entityName), relationship, newRelationship));
              } catch (error) {
                e = error;
                throw new Error('relationship ' + entityTo.name + '->' + change + ' not found in version ' + modelTo.version);
              }
            }
          }
        }
      }
      if (entityFrom) {
        ref11 = entityFrom.relationships;
        for (r = 0, len8 = ref11.length; r < len8; r++) {
          relationship = ref11[r];
          inverseRelationship = relationship.inverseRelationship();
          reflexiveRelationship = this._relationshipByPriority(relationship, inverseRelationship);
          reflexiveTableName = this._formatTableName(reflexiveRelationship.entity.name) + '_' + reflexiveRelationship.name;
          if (relationship.toMany && inverseRelationship.toMany) {
            change = ((ref12 = migration.relationshipsChanges[entityName]) != null ? ref12[relationship.name] : void 0) || ((ref13 = migration.relationshipsChanges[inverseRelationship.entity.name]) != null ? ref13[inverseRelationship.name] : void 0);
            if (change) {
              switch (change) {
                case '+':
                  break;
                case '-':
                  sqls.push(this._dropTableQuery(reflexiveTableName));
              }
            }
          }
        }
        ref14 = entityFrom.relationships;
        for (s = 0, len9 = ref14.length; s < len9; s++) {
          relationship = ref14[s];
          inverseRelationship = relationship.inverseRelationship();
          reflexiveRelationship = this._relationshipByPriority(relationship, inverseRelationship);
          reflexiveTableName = this._formatTableName(reflexiveRelationship.entity.name) + '_' + reflexiveRelationship.name;
          if (relationship.toMany && inverseRelationship.toMany) {
            change = (ref15 = migration.relationshipsChanges[entityName]) != null ? ref15[relationship.name] : void 0;
            if (change && (change !== '+' && change !== '-')) {
              newRelationship = entityTo.getRelationship(change);
              newInverseRelationship = newRelationship.inverseRelationship();
              newReflexiveRelationship = this._relationshipByPriority(newRelationship, newInverseRelationship);
              reflexiveRelationship = this._relationshipByPriority(relationship, inverseRelationship);
              reflexiveTableName = this.quoteSymbol + this._formatTableName(reflexiveRelationship.entity.name) + '_' + reflexiveRelationship.name + this.quoteSymbol;
              newReflexiveTableName = this.quoteSymbol + this._formatTableName(newReflexiveRelationship.entity.name) + '_' + newReflexiveRelationship.name + this.quoteSymbol;
              sqls.push('ALTER TABLE ' + reflexiveTableName + ' RENAME TO ' + newReflexiveTableName);
            }
          }
        }
      }
    }
    ref16 = modelFrom.entities;
    for (entityName in ref16) {
      entityFrom = ref16[entityName];
      ref17 = entityFrom.relationships;
      for (t = 0, len10 = ref17.length; t < len10; t++) {
        relationship = ref17[t];
        inverseRelationship = relationship.inverseRelationship();
        if (!relationship.toMany) {
          change = ((ref18 = migration.relationshipsChanges[entityName]) != null ? ref18[relationship.name] : void 0) || ((ref19 = migration.relationshipsChanges[inverseRelationship.entity.name]) != null ? ref19[inverseRelationship.name] : void 0);
          if (change) {
            switch (change) {
              case '+':
                break;
              case '-':
                sqls.push(this._removeRelationshipQuery(relationship.entity.name, relationship));
            }
          }
        }
      }
    }
    ref20 = modelTo.entities;
    for (entityName in ref20) {
      entityTo = ref20[entityName];
      if (entityTo && (ref21 = entityTo.name, indexOf.call(addedEntitiesNames, ref21) < 0)) {
        ref22 = entityTo.relationships;
        for (u = 0, len11 = ref22.length; u < len11; u++) {
          relationship = ref22[u];
          inverseRelationship = relationship.inverseRelationship();
          if (!relationship.toMany) {
            change = ((ref23 = migration.relationshipsChanges[entityName]) != null ? ref23[relationship.name] : void 0) || ((ref24 = migration.relationshipsChanges[inverseRelationship.entity.name]) != null ? ref24[inverseRelationship.name] : void 0);
            switch (change) {
              case '+':
                changedRelationshipsSqls = changedRelationshipsSqls.concat(this._addRelationshipQueries(relationship.entity.name, relationship));
                break;
            }
          }
        }
      }
      ref25 = entityTo.relationships;
      for (v = 0, len12 = ref25.length; v < len12; v++) {
        relationship = ref25[v];
        inverseRelationship = relationship.inverseRelationship();
        if (relationship.toMany && inverseRelationship.toMany) {
          change = ((ref26 = migration.relationshipsChanges[entityName]) != null ? ref26[relationship.name] : void 0) || ((ref27 = migration.relationshipsChanges[inverseRelationship.entity.name]) != null ? ref27[inverseRelationship.name] : void 0);
          if (change === '+') {
            changedRelationshipsSqls = changedRelationshipsSqls.concat(this.createRelationshipQueries(relationship));
          }
        }
      }
    }
    sqls = sqls.concat(changedRelationshipsSqls);
    return _.uniq(sqls);
  };

  GenericSQLStore.prototype._dropTableQuery = function(tableName) {
    return 'DROP TABLE IF EXISTS ' + this.quoteSymbol + tableName + this.quoteSymbol;
  };

  GenericSQLStore.prototype._dropEntityQueries = function(entity) {
    return [this._dropTableQuery(this._formatTableName(entity.name))];
  };

  GenericSQLStore.prototype._renameRelationshipQuery = function(tableName, relationshipFrom, relationshipTo) {
    return 'ALTER TABLE ' + this.quoteSymbol + tableName + this.quoteSymbol + ' RENAME COLUMN ' + this.quoteSymbol + relationshipFrom.name + '_id' + this.quoteSymbol + ' TO ' + this.quoteSymbol + relationshipTo.name + '_id' + this.quoteSymbol;
  };

  GenericSQLStore.prototype._renameAttributeQuery = function(tableName, attributeFrom, attributeTo) {
    return 'ALTER TABLE ' + this.quoteSymbol + tableName + this.quoteSymbol + ' RENAME COLUMN ' + this.quoteSymbol + attributeFrom.name + this.quoteSymbol + ' TO ' + this.quoteSymbol + attributeTo.name + this.quoteSymbol;
  };

  GenericSQLStore.prototype._removeColumnQuery = function(entityName, column) {
    return 'ALTER TABLE ' + this.quoteSymbol + this._formatTableName(entityName) + this.quoteSymbol + ' DROP COLUMN ' + this.quoteSymbol + column + this.quoteSymbol;
  };

  GenericSQLStore.prototype._removeRelationshipQuery = function(entityName, relationship) {
    var inverseRelationship, reflexiveRelationship, reflexiveTableName;
    inverseRelationship = relationship.inverseRelationship();
    if (relationship.toMany && inverseRelationship.toMany) {
      reflexiveRelationship = this._relationshipByPriority(relationship, inverseRelationship);
      reflexiveTableName = this._formatTableName(reflexiveRelationship.entity.name) + '_' + reflexiveRelationship.name;
      return this._dropTableQuery(reflexiveTableName);
    } else {
      return this._removeColumnQuery(entityName, relationship.name + '_id');
    }
  };

  GenericSQLStore.prototype._addRelationshipQueries = function(entityName, relationship) {
    return ['ALTER TABLE ' + this.quoteSymbol + this._formatTableName(entityName) + this.quoteSymbol + ' ADD COLUMN ' + this._relationshipColumnDefinition(relationship)];
  };

  GenericSQLStore.prototype.createEntityRelationshipQueries = function(entity, force) {
    var key, ref, relationship, sqls;
    sqls = [];
    ref = entity.relationships;
    for (key in ref) {
      relationship = ref[key];
      sqls = sqls.concat(this.createRelationshipQueries(relationship, force));
    }
    return sqls;
  };

  GenericSQLStore.prototype.createRelationshipQueries = function(relationship, force) {
    var inverseRelationship, reflexiveRelationship, reflexiveTableName, sqls;
    sqls = [];
    if (relationship.toMany) {
      inverseRelationship = relationship.inverseRelationship();
      if (inverseRelationship.toMany) {
        reflexiveRelationship = this._relationshipByPriority(relationship, inverseRelationship);
        reflexiveTableName = this._getMiddleTableNameForManyToManyRelation(reflexiveRelationship);
        sqls.push('CREATE TABLE IF NOT EXISTS `' + reflexiveTableName + '` (`' + reflexiveRelationship.name + '_id` int(11) NOT NULL,`reflexive` int(11) NOT NULL, PRIMARY KEY (`' + reflexiveRelationship.name + '_id`,`reflexive`))');
      }
    }
    return sqls;
  };

  GenericSQLStore.prototype._relationshipColumnDefinition = function(relationship) {
    return this.quoteSymbol + relationship.name + '_id' + this.quoteSymbol + ' int(11) DEFAULT NULL';
  };

  GenericSQLStore.prototype._runRawQueriesInSingleTransaction = function(sqls, transaction, callback) {
    var run;
    if (typeof transaction === 'function') {
      callback = transaction;
      transaction = void 0;
    }
    run = (function(_this) {
      return function(transaction) {
        return async.forEachSeries(sqls, function(sql, cb) {
          return transaction.query(sql, cb);
        }, function(err) {
          if (err) {
            return transaction.rollback(function() {
              if (callback) {
                callback(err);
              }
              return _this.connectionPool.releaseTransaction(transaction);
            });
          } else {
            return transaction.commit(function() {
              callback();
              return _this.connectionPool.releaseTransaction(transaction);
            });
          }
        });
      };
    })(this);
    if (transaction) {
      return run(transaction);
    }
    return this.connectionPool.createTransaction((function(_this) {
      return function(err, transaction) {
        if (err) {
          return callback(err);
        }
        return run(transaction);
      };
    })(this));
  };

  return GenericSQLStore;

})(IncrementalStore);

module.exports = GenericSQLStore;
