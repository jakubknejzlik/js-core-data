PersistentStoreCoordinator = require('./PersistentStoreCoordinator')
ManagedObjectModel = require('./ManagedObjectModel')
ManagedObjectContext = require('./ManagedObjectContext')
ManagedObject = require('./ManagedObject')
Predicate = require('./FetchClasses/Predicate')
EntityDescription = require('./Descriptors/EntityDescription')
AttributeDescription = require('./Descriptors/AttributeDescription')
AttributeType = require('./Descriptors/AttributeType')
RelationshipDescription = require('./Descriptors/RelationshipDescription')
ModelYamlParser = require('./Parsers/ModelYamlParser')
Pool = require('generic-pool')
url = require('url')
async = require('async')
Promise = require('bluebird')
convert = require('unit-converter')

class CoreData
  @registerType:(type)->
    AttributeDescription.registerType(type)

  constructor:(@storeURL,@options = {})->
    @modelVersion = 'default'
    if (@options.logging and typeof @options.logging isnt 'function')
      @options.logging = console.log
    @models = {}

  closeAllConnections: ()->
    return new Promise((resolve,reject)=>
      async.forEach(@_persistentStoreCoordinator().persistentStores,(store,cb)->
        store.closeAllConnections(cb)
      ,(err)->
        return reject(err) if err
        resolve()
      )
    )

  _ensureModel: ()->
    if not @model
      @model = @createModel()
    return @model

  setModelVersion:(version)->
    if not @models[version]
      throw new Error('unknown model version ' + version)
    @modelVersion = version
    @model = @models[@modelVersion]
    @persistentStoreCoordinator = null

  createModelFromYaml:(yamlSource, objectClasses, modelVersion) ->
    modelVersion = modelVersion or @modelVersion
    model = @createModel(modelVersion)
    ModelYamlParser.fillModelFromYaml(model,yamlSource,objectClasses)
    return model
  createModel:(modelVersion)->
    modelVersion = modelVersion or @modelVersion
    @models[modelVersion] = new ManagedObjectModel(modelVersion)

    if not @model
      @model = @models[modelVersion]

    return @models[modelVersion]

  getModel:(modelVersion)->
    if not @models[modelVersion]
      throw new Error('model with version ' + modelVersion + ' not found')
    return @models[modelVersion]

  defineEntity:(entityName,attributes,options = {})->
    return @_ensureModel().defineEntity(entityName,attributes,options)

  defineRelationship:(entity,destinationEntity,name,options = {})->
    @_ensureModel().defineRelationship(entity,destinationEntity,name,options)

  defineRelationshipToMany:(entity,destinationEntity,name,inverse,options)->
    @_ensureModel().defineRelationshipToMany(entity,destinationEntity,name,inverse,options)

  defineRelationshipToOne:(entity,destinationEntity,name,inverse,options)->
    @_ensureModel().defineRelationshipToOne(entity,destinationEntity,name,inverse,options)

  defineRelationshipOneToMany:(entity,destinationEntity,name,inverse,options)->
    @_ensureModel().defineRelationshipOneToMany(entity,destinationEntity,name,inverse,options)

  defineRelationshipManyToOne:(entity,destinationEntity,name,inverse,options)->
    @_ensureModel().defineRelationshipManyToOne(entity,destinationEntity,name,inverse,options)

  defineRelationshipManyToMany:(entity,destinationEntity,name,inverse,options)->
    @_ensureModel().defineRelationshipManyToMany(entity,destinationEntity,name,inverse,options)

  createContext:()->
    return new ManagedObjectContext(@_persistentStoreCoordinator())

  _persistentStoreCoordinator:()->
    if not @persistentStoreCoordinator
      @persistentStoreCoordinator = new PersistentStoreCoordinator(@model,@options)
      @persistentStoreCoordinator.addStore(@storeURL)
    return @persistentStoreCoordinator


  middleware:(options)->
    options = options or {}
    destroyTimeout = convert(options.destroyTimeout or '10s').to('ms')
    return (req,res,next)=>
      if @options.logging
        @options.logging('creating context')
      context = @createContext()
      req.context = context
      res.once('close',=>
        if context.destroyed
          return
        if @options.logging
          @options.logging('destroying context timeout (close): ',destroyTimeout)
        setTimeout(()->
          context.destroy()
        ,destroyTimeout)
      )
      res.once('finish',=>
        if context.destroyed
          return
        if @options.logging
          @options.logging('destroying context timeout (finish): ',destroyTimeout)
        setTimeout(()->
          context.destroy()
        ,destroyTimeout)
      )
      next()



CoreData.PersistentStoreCoordinator = PersistentStoreCoordinator
CoreData.ManagedObjectModel = ManagedObjectModel
CoreData.ManagedObjectContext = ManagedObjectContext
CoreData.ManagedObject = ManagedObject
CoreData.Predicate = Predicate
CoreData.AttributeType = AttributeType
CoreData.debug = process.env.NOD_ENV isnt 'production'


module.exports = CoreData