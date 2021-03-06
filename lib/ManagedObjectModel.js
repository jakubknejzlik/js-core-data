// Generated by CoffeeScript 1.10.0
(function() {
  var EntityDescription,
    ManagedObject,
    ManagedObjectModel,
    MigrationDescription,
    ModelYamlParser,
    RelationshipDescription,
    fs,
    path,
    util,
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

  EntityDescription = require("./Descriptors/EntityDescription");

  RelationshipDescription = require("./Descriptors/RelationshipDescription");

  MigrationDescription = require("./Descriptors/MigrationDescription");

  ManagedObject = require("./ManagedObject");

  ModelYamlParser = require("./Parsers/ModelYamlParser");

  path = require("path");

  fs = require("fs");

  util = require("util");

  ManagedObjectModel = (function(superClass) {
    extend(ManagedObjectModel, superClass);

    function ManagedObjectModel(version1) {
      this.version = version1 != null ? version1 : "unknown";
      this.entities = {};
      this.classes = {};
      this.migrations = [];
    }

    ManagedObjectModel.prototype.addEntity = function(entity) {
      if (entity instanceof EntityDescription) {
        return (this.entities[entity.name] = entity);
      } else {
        throw Error("entity " + entity + " is not EntityDescription");
      }
    };

    ManagedObjectModel.prototype.getEntity = function(entityName) {
      return this.entities[entityName];
    };

    ManagedObjectModel.prototype.subclassForEntity = function(entityName) {
      let entity = this.entities[entityName];
      let Subclass = this.classes[entityName];

      if (Subclass) return Subclass;

      let ObjectClass = this._entityObjectClass(entity);
      if (
        typeof ObjectClass !== "function" ||
        (!(ObjectClass.prototype instanceof ManagedObject) &&
          ObjectClass !== ManagedObject)
      ) {
        throw new Error(
          `objectClass for entity ${entityName} is not instance of ManagedObject (${ObjectClass})`
        );
      }

      class GeneratedSubclass extends ObjectClass {
        // constructor(entity, managedObjectContext, _rawData) {
        //   super(entity, managedObjectContext, _rawData);
        // }
      }
      // Subclass = (function(superClass1) {
      //   extend(Subclass, superClass1);

      //   function Subclass() {
      //     console.log("???", typeof Subclass, entityName);
      //     return new Subclass.__super__.constructor.apply(this, arguments);
      //   }

      //   return Subclass;
      // })(ObjectClass);

      ref = entity.attributes;
      for (i = 0, len = ref.length; i < len; i++) {
        attribute = ref[i];
        ManagedObject.addAttributeDescription(GeneratedSubclass, attribute);
      }
      ref1 = entity.relationships;
      for (j = 0, len1 = ref1.length; j < len1; j++) {
        relationship = ref1[j];
        ManagedObject.addRelationshipDescription(
          GeneratedSubclass,
          relationship
        );
      }
      this.classes[entityName] = GeneratedSubclass;
      // console.log(entityName, GeneratedSubclass, "???");
      return GeneratedSubclass;
    };

    ManagedObjectModel.prototype._entityObjectClass = function(entity) {
      return entity.objectClass;
    };

    ManagedObjectModel.prototype.insertObjectIntoContext = function(
      entityName,
      context
    ) {
      var Subclass, entity, object;
      entity = this.entities[entityName];
      if (!entity) {
        throw new Error("entity with name '" + entityName + "' doesn't exists");
      }
      Subclass = this.subclassForEntity(entityName);
      object = new Subclass(entity, context);
      object.entity = entity;
      context.insertObject(object);
      return object;
    };

    ManagedObjectModel.prototype.defineEntity = function(
      entityName,
      attributes,
      options
    ) {
      var entity;
      if (options == null) {
        options = {};
      }
      options.columns = attributes;
      entity = new EntityDescription(entityName, options);
      this.addEntity(entity);
      return entity;
    };

    ManagedObjectModel.prototype.defineRelationship = function(
      entity,
      destinationEntity,
      name,
      options
    ) {
      var e, error, inverseRelationship, relationship;
      if (options == null) {
        options = {};
      }
      if (typeof entity === "string") {
        entity = this.entities[entity];
      }
      if (typeof destinationEntity === "string") {
        destinationEntity = this.entities[destinationEntity];
      }
      relationship = new RelationshipDescription(
        name,
        destinationEntity,
        options.toMany,
        options.inverse,
        entity,
        options.onDelete
      );
      entity.addRelationship(relationship);
      inverseRelationship = null;
      try {
        inverseRelationship = relationship.inverseRelationship();
      } catch (error) {
        e = error;
      }
      if (
        inverseRelationship &&
        !relationship.toMany &&
        !inverseRelationship.toMany
      ) {
        throw new Error(
          "oneToOne relationships are not supported " +
            relationship +
            ", " +
            inverseRelationship
        );
      }
    };

    ManagedObjectModel.prototype.defineRelationshipToMany = function(
      entity,
      destinationEntity,
      name,
      inverse,
      options
    ) {
      if (options == null) {
        options = {};
      }
      options.inverse = inverse;
      options.toMany = true;
      return this.defineRelationship(entity, destinationEntity, name, options);
    };

    ManagedObjectModel.prototype.defineRelationshipToOne = function(
      entity,
      destinationEntity,
      name,
      inverse,
      options
    ) {
      if (options == null) {
        options = {};
      }
      options.inverse = inverse;
      options.toMany = false;
      return this.defineRelationship(entity, destinationEntity, name, options);
    };

    ManagedObjectModel.prototype.defineRelationshipOneToMany = function(
      entity,
      destinationEntity,
      name,
      inverse,
      options
    ) {
      this.defineRelationshipToOne(
        destinationEntity,
        entity,
        inverse,
        name,
        options
      );
      return this.defineRelationshipToMany(
        entity,
        destinationEntity,
        name,
        inverse,
        options
      );
    };

    ManagedObjectModel.prototype.defineRelationshipManyToOne = function(
      entity,
      destinationEntity,
      name,
      inverse,
      options
    ) {
      this.defineRelationshipToMany(
        destinationEntity,
        entity,
        inverse,
        name,
        options
      );
      return this.defineRelationshipToOne(
        entity,
        destinationEntity,
        name,
        inverse,
        options
      );
    };

    ManagedObjectModel.prototype.defineRelationshipManyToMany = function(
      entity,
      destinationEntity,
      name,
      inverse,
      options
    ) {
      this.defineRelationshipToMany(
        entity,
        destinationEntity,
        name,
        inverse,
        options
      );
      if (inverse !== name) {
        return this.defineRelationshipToMany(
          destinationEntity,
          entity,
          inverse,
          name,
          options
        );
      }
    };

    ManagedObjectModel.prototype.createMigrationFrom = function(sourceModel) {
      var migration;
      migration = new MigrationDescription(sourceModel, this);
      this.migrations.push(migration);
      return migration;
    };

    ManagedObjectModel.prototype.createMigrationTo = function(targetModel) {
      var migration;
      migration = new MigrationDescription(this, targetModel);
      this.migrations.push(migration);
      return migration;
    };

    ManagedObjectModel.prototype.getMigrationsFrom = function(version) {
      var i, j, len, len1, migration, migrations, ref, ref1;
      ref = this.migrations;
      for (i = 0, len = ref.length; i < len; i++) {
        migration = ref[i];
        if (
          this.version === migration.modelTo.version &&
          version === migration.modelFrom.version
        ) {
          return [migration];
        }
      }
      ref1 = this.migrations;
      for (j = 0, len1 = ref1.length; j < len1; j++) {
        migration = ref1[j];
        if ((migration.modelTo.version = this.version)) {
          migrations = migration.modelFrom.getMigrationsFrom(version);
          if ((migrations != null ? migrations.length : void 0) > 0) {
            migrations.push(migration);
            return migrations;
          }
        }
      }
      return null;
    };

    return ManagedObjectModel;
  })(Object);

  module.exports = ManagedObjectModel;
}.call(this));
