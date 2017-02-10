EntityDescription = require('./Descriptors/EntityDescription')
RelationshipDescription = require('./Descriptors/RelationshipDescription')
MigrationDescription = require('./Descriptors/MigrationDescription')
ManagedObject = require('./ManagedObject')
ModelYamlParser = require('./Parsers/ModelYamlParser')
path = require('path')
fs = require('fs')
util = require('util')

class ManagedObjectModel extends Object
  constructor:(@version = 'unknown') ->
    @entities = {}
    @classes = {}
    @migrations = []

  addEntity:(entity) ->
    if entity instanceof EntityDescription
      @entities[entity.name] = entity
    else
      throw Error 'entity ' + entity + ' is not EntityDescription'

  getEntity: (entityName)->
    @entities[entityName]

  subclassForEntity:(entityName)->
    entity = @entities[entityName]
    Subclass = @classes[entityName]



    if not Subclass
      ObjectClass = @_entityObjectClass(entity)
      if typeof ObjectClass isnt 'function' or (ObjectClass.prototype not instanceof ManagedObject and ObjectClass isnt ManagedObject)
        throw new Error('objectClass for entity ' + entityName + ' is not instance of ManagedObject (' + ObjectClass + ')')
      class Subclass extends ObjectClass

      for attribute in entity.attributes
        Subclass.addAttributeDescription(attribute)
      for relationship in entity.relationships
        Subclass.addRelationshipDescription(relationship)

      @classes[entityName] = Subclass

    Subclass


  _entityObjectClass:(entity)->
    return entity.objectClass

  insertObjectIntoContext:(entityName,context) ->
    entity = @entities[entityName]
    if not entity
      throw new Error('entity with name \'' + entityName + '\' doesn\'t exists');
    Subclass = @subclassForEntity(entityName)

    object = new Subclass(entity,context)
    object.entity = entity

    context.insertObject(object)

    object




  defineEntity:(entityName,attributes,options = {})->
    options.columns = attributes
    entity = new EntityDescription(entityName,options);
    @addEntity(entity)

    return entity

  defineRelationship:(entity,destinationEntity,name,options = {})->
    if typeof entity is 'string'
      entity = @entities[entity]
    if typeof destinationEntity is 'string'
      destinationEntity = @entities[destinationEntity]
#    console.log(entity.name,'=>',name,'=>',destinationEntity.name,'toMany:',options.toMany,'inverse:',options.inverse)
    relationship = new RelationshipDescription(name,destinationEntity,options.toMany,options.inverse,entity,options.onDelete);
    entity.addRelationship(relationship)
    inverseRelationship = null
    try
      inverseRelationship = relationship.inverseRelationship()
    catch e

    if inverseRelationship and not relationship.toMany and not inverseRelationship.toMany
      throw new Error('oneToOne relationships are not supported ' + relationship + ', ' + inverseRelationship)

  defineRelationshipToMany:(entity,destinationEntity,name,inverse,options = {})->
    options.inverse = inverse
    options.toMany = yes
    @defineRelationship(entity,destinationEntity,name,options)

  defineRelationshipToOne:(entity,destinationEntity,name,inverse,options = {})->
    options.inverse = inverse
    options.toMany = no
    @defineRelationship(entity,destinationEntity,name,options)

  defineRelationshipOneToMany:(entity,destinationEntity,name,inverse,options)->
    @defineRelationshipToOne(destinationEntity,entity,inverse,name,options)
    @defineRelationshipToMany(entity,destinationEntity,name,inverse,options)

  defineRelationshipManyToOne:(entity,destinationEntity,name,inverse,options)->
    @defineRelationshipToMany(destinationEntity,entity,inverse,name,options)
    @defineRelationshipToOne(entity,destinationEntity,name,inverse,options)

  defineRelationshipManyToMany:(entity,destinationEntity,name,inverse,options)->
    @defineRelationshipToMany(entity,destinationEntity,name,inverse,options)
    if inverse isnt name
      @defineRelationshipToMany(destinationEntity,entity,inverse,name,options)



  createMigrationFrom:(sourceModel)->
    migration = new MigrationDescription(sourceModel,@)
    @migrations.push(migration)
    return migration

  createMigrationTo:(targetModel)->
    migration = new MigrationDescription(@,targetModel)
    @migrations.push(migration)
    return migration


  getMigrationsFrom:(version)->
    for migration in @migrations
      if @version is migration.modelTo.version and version is migration.modelFrom.version
        return [migration]

    for migration in @migrations
      if migration.modelTo.version = @version
        migrations = migration.modelFrom.getMigrationsFrom(version)
        if migrations?.length > 0
          migrations.push(migration)
          return migrations

    return null

module.exports = ManagedObjectModel;