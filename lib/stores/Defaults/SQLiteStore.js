var GenericPool,
  GenericSQLStore,
  ManagedObjectID,
  PersistentStoreRequest,
  Predicate,
  SQLConnection,
  SQLiteConnection,
  SQLiteStore,
  _,
  async,
  e,
  error,
  privateTableNames,
  sqlite,
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
  hasProp = {}.hasOwnProperty,
  indexOf =
    [].indexOf ||
    function(item) {
      for (var i = 0, l = this.length; i < l; i++) {
        if (i in this && this[i] === item) return i;
      }
      return -1;
    };

GenericSQLStore = require("./GenericSQLStore");

PersistentStoreRequest = require("./../PersistentStoreRequest");

GenericPool = require("generic-pool");

async = require("async");

ManagedObjectID = require("./../../ManagedObjectID");

Predicate = require("./../../FetchClasses/Predicate");

SQLConnection = require("./SQLConnection");

try {
  require("sqlite3");
} catch (error) {
  e = error;
  throw new Error(
    "sqlite3 module is required to use SQLite storage, please install it by running npm install --save sqlite3"
  );
}

sqlite = require("sqlite3");

_ = require("underscore");

_.mixin(require("underscore.inflections"));

privateTableNames = ["sqlite_sequence"];

SQLiteStore = (function(superClass) {
  extend(SQLiteStore, superClass);

  function SQLiteStore() {
    return SQLiteStore.__super__.constructor.apply(this, arguments);
  }

  SQLiteStore.prototype.createConnection = function(url) {
    return new SQLiteConnection(url, this);
  };

  SQLiteStore.prototype._insertQueryForManyToMany = function(
    relationship,
    object,
    addedObject
  ) {
    return (
      "INSERT OR IGNORE INTO " +
      this.quoteSymbol +
      this._getMiddleTableNameForManyToManyRelation(relationship) +
      this.quoteSymbol +
      " (reflexive," +
      this.quoteSymbol +
      relationship.name +
      "_id" +
      this.quoteSymbol +
      ") VALUES (" +
      this._recordIDForObjectID(object.objectID) +
      "," +
      this._recordIDForObjectID(addedObject.objectID) +
      ")"
    );
  };

  SQLiteStore.prototype.createSchemaQueries = function(
    options,
    transaction,
    callback
  ) {
    var sqls;
    if (options == null) {
      options = {};
    }
    sqls = [];
    return transaction.query(
      "SELECT name as table_name FROM sqlite_master WHERE type='table'",
      (function(_this) {
        return function(err, rows) {
          var entity, error1, i, key, len, objectModel, ref, ref1, ref2, row;
          if (err) {
            return callback(err);
          }
          if (options.force) {
            for (i = 0, len = rows.length; i < len; i++) {
              row = rows[i];
              if (
                ((ref = row["table_name"]),
                indexOf.call(privateTableNames, ref) < 0)
              ) {
                sqls.push(_this._dropTableQuery(row["table_name"]));
              }
            }
          }
          try {
            objectModel = _this.storeCoordinator.objectModel;
            ref1 = objectModel.entities;
            for (key in ref1) {
              entity = ref1[key];
              sqls = sqls.concat(
                _this.createEntityQueries(entity, options.force)
              );
            }
            ref2 = objectModel.entities;
            for (key in ref2) {
              entity = ref2[key];
              sqls = sqls.concat(
                _this.createEntityRelationshipQueries(entity, options.force)
              );
            }
            sqls.push(
              "CREATE TABLE IF NOT EXISTS `_meta` (`key` varchar(10) NOT NULL,`value` varchar(250) NOT NULL,PRIMARY KEY (`key`))"
            );
            sqls.push(
              "INSERT OR IGNORE INTO `_meta` VALUES('version','" +
                objectModel.version +
                "')"
            );
            return callback(null, sqls);
          } catch (error1) {
            err = error1;
            return callback(err);
          }
        };
      })(this)
    );
  };

  SQLiteStore.prototype.createEntityQueries = function(entity, force, options) {
    var attribute,
      columnDefinition,
      i,
      index,
      j,
      k,
      len,
      len1,
      len2,
      parts,
      ref,
      ref1,
      ref2,
      relationship,
      sql,
      sqls,
      tableName;
    if (force == null) {
      force = false;
    }
    if (options == null) {
      options = {};
    }
    sqls = [];
    tableName = this._formatTableName(entity.name);
    parts = [
      "`" + ManagedObjectID.idColumnName + "` INTEGER PRIMARY KEY AUTOINCREMENT"
    ];
    ref = entity.getNonTransientAttributes();
    for (i = 0, len = ref.length; i < len; i++) {
      attribute = ref[i];
      columnDefinition = this._columnDefinitionForAttribute(attribute);
      if (columnDefinition) {
        parts.push(columnDefinition);
      } else {
        throw new Error("unknown attribute type " + attribute.type);
      }
    }
    if (!options.noRelationships) {
      ref1 = entity.relationships;
      for (j = 0, len1 = ref1.length; j < len1; j++) {
        relationship = ref1[j];
        if (!relationship.toMany) {
          parts.push(
            "`" +
              relationship.name +
              "_id` int(11) DEFAULT NULL REFERENCES `" +
              this._formatTableName(relationship.destinationEntity.name) +
              "`(`" +
              ManagedObjectID.idColumnName +
              "`) ON DELETE " +
              relationship.getOnDeleteRule()
          );
        }
      }
    }
    sql = "CREATE TABLE IF NOT EXISTS `" + tableName + "` (";
    sql += parts.join(",");
    sql += ")";
    ref2 = this._indexesForEntity(entity);
    for (k = 0, len2 = ref2.length; k < len2; k++) {
      index = ref2[k];
      sql +=
        ";CREATE " +
        (index.type === "unique" ? "UNIQUE" : "") +
        " INDEX IF NOT EXISTS `" +
        index.name +
        "` ON `" +
        tableName +
        "` (`" +
        index.columns.join("`,`") +
        "`)";
    }
    sqls.push(sql);
    if (!options.ignoreRelationships) {
      sqls = sqls.concat(this.createEntityRelationshipQueries(entity, force));
    }
    return sqls;
  };

  SQLiteStore.prototype.createRelationshipQueries = function(
    relationship,
    force
  ) {
    var inversedRelationship,
      parts,
      reflexiveRelationship,
      reflexiveTableName,
      sqls;
    sqls = [];
    if (relationship.toMany) {
      inversedRelationship = relationship.inverseRelationship();
      if (inversedRelationship.toMany) {
        reflexiveRelationship = this._relationshipByPriority(
          relationship,
          inversedRelationship
        );
        reflexiveTableName = this._getMiddleTableNameForManyToManyRelation(
          reflexiveRelationship
        );
        parts = [];
        parts.push(
          "`" +
            reflexiveRelationship.name +
            "_id` int(11) NOT NULL REFERENCES `" +
            this._formatTableName(
              reflexiveRelationship.destinationEntity.name
            ) +
            "`(`" +
            ManagedObjectID.idColumnName +
            "`) ON DELETE CASCADE"
        );
        parts.push(
          "`reflexive` int(11) NOT NULL REFERENCES `" +
            this._formatTableName(reflexiveRelationship.entity.name) +
            "`(`" +
            ManagedObjectID.idColumnName +
            "`) ON DELETE CASCADE"
        );
        parts.push(
          "PRIMARY KEY (`" + reflexiveRelationship.name + "_id`,`reflexive`)"
        );
        sqls.push(
          "CREATE TABLE IF NOT EXISTS `" +
            reflexiveTableName +
            "` (" +
            parts.join(",") +
            ")"
        );
      }
    }
    return sqls;
  };

  SQLiteStore.prototype.createMigrationQueries = function(migration) {
    var attribute,
      change,
      entityChangedNames,
      entityFrom,
      entityName,
      entityTo,
      error1,
      error2,
      error3,
      error4,
      i,
      inversedRelationship,
      j,
      k,
      l,
      len,
      len1,
      len2,
      len3,
      len4,
      len5,
      len6,
      m,
      modelFrom,
      modelTo,
      n,
      newAttribute,
      newColumnNames,
      newRelationship,
      o,
      oldColumnNames,
      oldInversedRelationship,
      oldReflexiveRelationship,
      oldReflexiveTableName,
      oldRelationship,
      ref,
      ref1,
      ref10,
      ref2,
      ref3,
      ref4,
      ref5,
      ref6,
      ref7,
      ref8,
      ref9,
      reflexiveRelationship,
      reflexiveTableName,
      relationship,
      sqls,
      tableName,
      tmpTableName,
      updatedEntities;
    sqls = [];
    entityChangedNames = {};
    modelTo = migration.modelTo;
    modelFrom = migration.modelFrom;
    ref = migration.entitiesChanges;
    for (i = 0, len = ref.length; i < len; i++) {
      change = ref[i];
      entityName = change.entity;
      switch (change.change) {
        case "+":
          sqls = sqls.concat(
            this.createEntityQueries(modelTo.getEntity(entityName))
          );
          break;
        case "-":
          sqls.push(
            "DROP TABLE IF EXISTS " +
              this.quoteSymbol +
              this._formatTableName(entityName) +
              this.quoteSymbol
          );
          break;
        default:
          entityChangedNames[change.change] = entityName;
          sqls.push(
            "ALTER TABLE " +
              this.quoteSymbol +
              this._formatTableName(entityName) +
              this.quoteSymbol +
              " RENAME TO " +
              this.quoteSymbol +
              this._formatTableName(change.change) +
              this.quoteSymbol
          );
      }
    }
    updatedEntities = _.uniq(
      Object.keys(migration.attributesChanges).concat(
        Object.keys(migration.relationshipsChanges)
      )
    );
    for (j = 0, len1 = updatedEntities.length; j < len1; j++) {
      entityName = updatedEntities[j];
      entityTo =
        modelTo.getEntity(entityName) ||
        modelTo.getEntity(entityChangedNames[entityName]);
      entityFrom =
        modelFrom.getEntity(entityName) ||
        modelFrom.getEntity(entityChangedNames[entityName]);
      oldColumnNames = [ManagedObjectID.idColumnName];
      newColumnNames = [ManagedObjectID.idColumnName];
      ref1 = entityFrom.getNonTransientAttributes();
      for (k = 0, len2 = ref1.length; k < len2; k++) {
        attribute = ref1[k];
        change =
          (ref2 = migration.attributesChanges[entityName]) != null
            ? ref2[attribute.name]
            : void 0;
        if (change) {
          if (change !== "-" && change !== "+") {
            oldColumnNames.push(attribute.name);
            newColumnNames.push(change);
          }
        } else if (change !== "+") {
          try {
            newAttribute = entityTo.getAttribute(attribute.name);
            oldColumnNames.push(attribute.name);
            newColumnNames.push(newAttribute.name);
          } catch (error1) {
            e = error1;
            throw new Error(
              "attribute " +
                entityFrom.name +
                "->" +
                attribute.name +
                " not found in version " +
                modelFrom.migrateVersions
            );
          }
        }
      }
      ref3 = entityTo.getNonTransientAttributes();
      for (l = 0, len3 = ref3.length; l < len3; l++) {
        attribute = ref3[l];
        change =
          (ref4 = migration.attributesChanges[entityName]) != null
            ? ref4[attribute.name]
            : void 0;
        if (change === "+") {
          try {
            newColumnNames.push(attribute.name);
            oldColumnNames.push(null);
          } catch (error2) {
            e = error2;
            throw new Error(
              "attribute " +
                entityFrom.name +
                "->" +
                attribute.name +
                " not found in version " +
                modelFrom.migrateVersions
            );
          }
        }
      }
      ref5 = entityFrom.relationships;
      for (m = 0, len4 = ref5.length; m < len4; m++) {
        relationship = ref5[m];
        if (!relationship.toMany) {
          change =
            (ref6 = migration.relationshipsChanges[entityName]) != null
              ? ref6[relationship.name]
              : void 0;
          if (change) {
            if (change !== "-" && change !== "+") {
              oldColumnNames.push(relationship.name + "_id");
              newColumnNames.push(change + "_id");
            }
          } else if (change !== "+") {
            try {
              newRelationship = entityTo.getRelationship(relationship.name);
              oldColumnNames.push(relationship.name + "_id");
              newColumnNames.push(newRelationship.name + "_id");
            } catch (error3) {
              e = error3;
              throw new Error(
                "relationship " +
                  entityFrom.name +
                  "->" +
                  relationship.name +
                  " not found in version " +
                  modelFrom.migrateVersions
              );
            }
          }
        }
      }
      ref7 = entityTo.relationships;
      for (n = 0, len5 = ref7.length; n < len5; n++) {
        relationship = ref7[n];
        if (!relationship.toMany) {
          change =
            (ref8 = migration.relationshipsChanges[entityName]) != null
              ? ref8[relationship.name]
              : void 0;
          if (change === "+") {
            try {
              newColumnNames.push(relationship.name + "_id");
              oldColumnNames.push(null);
            } catch (error4) {
              e = error4;
              throw new Error(
                "relationship " +
                  entityFrom.name +
                  "->" +
                  relationship.name +
                  " not found in version " +
                  modelFrom.migrateVersions
              );
            }
          }
        }
      }
      tableName =
        this.quoteSymbol + this._formatTableName(entityName) + this.quoteSymbol;
      tmpTableName =
        this.quoteSymbol +
        this._formatTableName(entityName) +
        "_tmp" +
        this.quoteSymbol;
      sqls.push("ALTER TABLE " + tableName + " RENAME TO " + tmpTableName);
      sqls = sqls.concat(
        this.createEntityQueries(entityTo, false, {
          ignoreRelationships: true
        })
      );
      sqls.push(
        "INSERT INTO " +
          tableName +
          " (" +
          this.quoteSymbol +
          newColumnNames.join(this.quoteSymbol + "," + this.quoteSymbol) +
          this.quoteSymbol +
          ") SELECT " +
          this.quoteSymbol +
          oldColumnNames.join(this.quoteSymbol + "," + this.quoteSymbol) +
          this.quoteSymbol +
          " FROM " +
          tmpTableName
      );
      sqls.push("DROP TABLE " + tmpTableName);
      ref9 = entityTo.relationships;
      for (o = 0, len6 = ref9.length; o < len6; o++) {
        relationship = ref9[o];
        inversedRelationship = relationship.inverseRelationship();
        if (relationship.toMany && inversedRelationship.toMany) {
          change =
            (ref10 = migration.relationshipsChanges[entityName]) != null
              ? ref10[relationship.name]
              : void 0;
          if (change) {
            if (change !== "+" && change !== "-") {
              oldRelationship = entityFrom.getRelationship(change);
              oldInversedRelationship = oldRelationship.inverseRelationship();
              oldReflexiveRelationship = this._relationshipByPriority(
                oldRelationship,
                oldInversedRelationship
              );
              reflexiveRelationship = this._relationshipByPriority(
                relationship,
                inversedRelationship
              );
              oldReflexiveTableName =
                this.quoteSymbol +
                this._formatTableName(oldReflexiveRelationship.entity.name) +
                "_" +
                oldReflexiveRelationship.name +
                this.quoteSymbol;
              reflexiveTableName =
                this.quoteSymbol +
                this._formatTableName(reflexiveRelationship.entity.name) +
                "_" +
                reflexiveRelationship.name +
                this.quoteSymbol;
              sqls.push(
                "ALTER TABLE " +
                  oldReflexiveTableName +
                  " RENAME TO " +
                  reflexiveTableName
              );
            }
          } else {
            sqls = sqls.concat(this.createEntityRelationshipQueries(entityTo));
          }
        }
      }
    }
    return sqls;
  };

  return SQLiteStore;
})(GenericSQLStore);

SQLiteConnection = (function(superClass) {
  extend(SQLiteConnection, superClass);

  function SQLiteConnection() {
    return SQLiteConnection.__super__.constructor.apply(this, arguments);
  }

  SQLiteConnection.prototype.connect = function(callback) {
    return (this.connection = new sqlite.Database(
      this.url.replace("sqlite://", ""),
      (function(_this) {
        return function(err) {
          if (err) {
            return callback(err);
          }
          return callback(null, _this.connection);
        };
      })(this)
    ));
  };

  SQLiteConnection.prototype.close = function() {
    return this.connection.close();
  };

  SQLiteConnection.prototype.execute = function(query, callback) {
    return this.connection.all(query, callback);
  };

  SQLiteConnection.prototype.createRow = function(tableName, id, callback) {
    let idValue = id || "NULL";
    let query = `INSERT INTO \`${tableName}\` (\`${ManagedObjectID.idColumnName}\`) VALUES (${idValue})`;
    this.log(query);
    return this.connection.run(query, function(err) {
      if (err) {
        return callback(err);
      }
      return callback(null, this.lastID);
    });
  };

  return SQLiteConnection;
})(SQLConnection);

module.exports = SQLiteStore;
