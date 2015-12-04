PersistentStoreCoordinator = require('./lib/PersistentStoreCoordinator')
ManagedObjectModel = require('./lib/ManagedObjectModel')
ManagedObjectContext = require('./lib/ManagedObjectContext')
ManagedObject = require('./lib/ManagedObject')
Predicate = require('./lib/FetchClasses/Predicate')
EntityDescription = require('./lib/Descriptors/EntityDescription')
AttributeDescription = require('./lib/Descriptors/AttributeDescription')
AttributeType = require('./lib/Descriptors/AttributeType')
RelationshipDescription = require('./lib/Descriptors/RelationshipDescription')
Pool = require('generic-pool')
url = require('url')
async = require('async')
Q = require('q')
convert = require('unit-converter')



class CoreData
  @registerType:(type)->
    AttributeDescription.registerType(type)

  constructor:(@storeURL,@options = {})->
    @modelVersion = 'default'
    if @options.logging is undefined or (@options.logging and typeof @options.logging isnt 'function')
      @options.logging = console.log
    @models = {}
    @model = @models[@modelVersion] = new ManagedObjectModel(@options.modelFile, @options.modelClasses, @modelVersion)

  syncSchema:(options,callback)->
    deferred = Q.defer()
    if typeof options is 'function'
      callback = options
      options = undefined
    options = options or {}
    async.forEach(@_persistentStoreCoordinator().persistentStores,(store,cb)->
      store.syncSchema(options,cb)
    ,(err)->
#      callback(err) if callback
      if err
        deferred.reject(err)
      else
        deferred.resolve()
    )
    return deferred.promise.nodeify(callback)

  setModelVersion:(version)->
    if not @models[version]
      throw new Error('unknown model version ' + version)
    @modelVersion = version
    @model = @models[@modelVersion]
    @persistentStoreCoordinator = null

  createModel:(modelVersion)->
    @models[modelVersion] = new ManagedObjectModel(null, null, modelVersion)
    return @models[modelVersion]

  defineEntity:(entityName,attributes,options = {})->
    return @model.defineEntity(entityName,attributes,options)

  defineRelationship:(entity,destinationEntity,name,options = {})->
    @model.defineRelationship(entity,destinationEntity,name,options)

  defineRelationshipToMany:(entity,destinationEntity,name,inverse,options)->
    @model.defineRelationshipToMany(entity,destinationEntity,name,inverse,options)

  defineRelationshipToOne:(entity,destinationEntity,name,inverse,options)->
    @model.defineRelationshipToOne(entity,destinationEntity,name,inverse,options)

  defineRelationshipOneToMany:(entity,destinationEntity,name,inverse,options)->
    @model.defineRelationshipOneToMany(entity,destinationEntity,name,inverse,options)

  defineRelationshipManyToOne:(entity,destinationEntity,name,inverse,options)->
    @model.defineRelationshipManyToOne(entity,destinationEntity,name,inverse,options)

  defineRelationshipManyToMany:(entity,destinationEntity,name,inverse,options)->
    @model.defineRelationshipManyToMany(entity,destinationEntity,name,inverse,options)

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
