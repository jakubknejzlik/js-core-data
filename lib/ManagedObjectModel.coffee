EntityDescription = require('./Descriptors/EntityDescription')
ManagedObject = require('./ManagedObject')
path = require('path')
fs = require('fs')
util = require('util')

class ManagedObjectModel extends Object
  constructor:(scheme = null,modelClasses) ->
    @entities = {}
    @classes = {}
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

module.exports = ManagedObjectModel;