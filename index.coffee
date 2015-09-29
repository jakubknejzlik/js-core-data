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



class CoreData
  @registerType:(type)->
    AttributeDescription.registerType(type)

  constructor:(@storeURL,@options = {})->
    if @options.logging is undefined
      @options.logging = console.log
    @model = new ManagedObjectModel(@options.modelFile, @options.modelClasses)

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

  defineEntity:(entityName,attributes,options = {})->
    return @model.defineEntity(entityName,attributes,options)

  defineRelationship:(entity,destinationEntity,name,options = {})->
    @model.defineRelationship(entity,destinationEntity,name,options)

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

  createContext:()->
    return new ManagedObjectContext(@_persistentStoreCoordinator())

  _persistentStoreCoordinator:()->
    if not @persistentStoreCoordinator
      @persistentStoreCoordinator = new PersistentStoreCoordinator(@model,@options)
      @persistentStoreCoordinator.addStore(@storeURL)
    return @persistentStoreCoordinator

  middleware:()->
    return (req,res,next)=>
      context = @createContext()
      req.context = context
      res.once('finish',->
        context.destroy()
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
