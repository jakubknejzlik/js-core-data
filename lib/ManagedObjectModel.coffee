EntityDescription = require('./Descriptors/EntityDescription')
RelationshipDescription = require('./Descriptors/RelationshipDescription')
MigrationDescription = require('./Descriptors/MigrationDescription')
ManagedObject = require('./ManagedObject')
path = require('path')
fs = require('fs')
util = require('util')

class ManagedObjectModel extends Object
  constructor:(scheme = null,modelClasses, @version = 'unknown') ->
    @entities = {}
    @classes = {}
    @migrations = []
    @modelClasses = modelClasses or {}
    if scheme
      if fs.existsSync(scheme)
        @loadSchemeFromUrl(scheme)
      else
        @loadSchemeFromYaml(scheme)

  loadSchemeFromUrl:(url) ->
    ext = path.extname(url)
    switch ext
      when '.yaml' then require('./Parsers/ModelYamlParser').fillModelFromYamlFile(@,url)
      else throw new Error('unknown extension '+ext)

    for key,entity of @entities
      @_entityObjectClass(entity)

  loadSchemeFromYaml:(yamlSource)->
    require('./Parsers/ModelYamlParser').fillModelFromYaml(@,yamlSource)

    for key,entity of @entities
      @_entityObjectClass(entity)


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
      objectClass = @_entityObjectClass(entity)
      class Subclass extends objectClass

      for attribute in entity.attributes
        Subclass.addAttributeDescription(attribute)
      for relationship in entity.relationships
        Subclass.addRelationshipDescription(relationship)

      @classes[entityName] = Subclass

    Subclass

  createMigrationTo:(targetModel)->
    migration = new MigrationDescription(@,targetModel)
    @migrations.push(migration)
    return migration
  createMigrationFrom:(sourceModel)->
    migration = new MigrationDescription(sourceModel,@)
    @migrations.push(migration)
    return migration

  _entityObjectClass:(entity)->
    if entity.objectClass
      return entity.objectClass
    objectClassName = entity.objectClassName
    cls = null
    if objectClassName
      if @modelClasses[objectClassName]
        cls = @modelClasses[objectClassName]
      else
        _m = module.parent
        loop
          try
            cls = require(path.dirname(_m.filename) + objectClassName)
          catch e
          _m = _m.parent
          break unless _m
    else
      cls = ManagedObject
    if not cls
      throw new Error('module for class ' + entity.name + ' not found')
    entity.objectClass = cls
    return cls

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
    relationship = new RelationshipDescription(name,destinationEntity,options.toMany,options.inverse,entity);
    entity.addRelationship(relationship)

  defineRelationshipToMany:(entity,destinationEntity,name,inverse)->
    @defineRelationship(entity,destinationEntity,name,{inverse:inverse,toMany:yes})

  defineRelationshipToOne:(entity,destinationEntity,name,inverse)->
    @defineRelationship(entity,destinationEntity,name,{inverse:inverse,toMany:no})

  defineRelationshipOneToMany:(entity,destinationEntity,name,inverse)->
    @defineRelationshipToOne(entity,destinationEntity,name,inverse)
    @defineRelationshipToMany(destinationEntity,entity,inverse,name)
  defineRelationshipManyToOne:(entity,destinationEntity,name,inverse)->
    @defineRelationshipToMany(entity,destinationEntity,name,inverse)
    @defineRelationshipToOne(destinationEntity,entity,inverse,name)
  defineRelationshipManyToMany:(entity,destinationEntity,name,inverse)->
    @defineRelationshipToMany(entity,destinationEntity,name,inverse)
    @defineRelationshipToMany(destinationEntity,entity,inverse,name)

module.exports = ManagedObjectModel;