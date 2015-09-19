PersistentStoreCoordinator = require('./lib/PersistentStoreCoordinator')
ManagedObjectModel = require('./lib/ManagedObjectModel')
ManagedObjectContext = require('./lib/ManagedObjectContext')
ManagedObject = require('./lib/ManagedObject')
Predicate = require('./lib/FetchClasses/Predicate')
EntityDescription = require('./lib/Descriptors/EntityDescription')
AttributeDescription = require('./lib/Descriptors/AttributeDescription')
RelationshipDescription = require('./lib/Descriptors/RelationshipDescription')
Pool = require('generic-pool')
url = require('url')
async = require('async')
Q = require('q')



class CoreData
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
    options.columns = attributes
    entity = new EntityDescription(entityName,options);
    @model.addEntity(entity)

    return entity

  defineRelationship:(entity,destinationEntity,name,options = {})->
    if typeof entity is 'string'
      entity = @model.entities[entity]
    if typeof destinationEntity is 'string'
      destinationEntity = @model.entities[destinationEntity]
    relationship = new RelationshipDescription(name,destinationEntity,options.toMany,options.inverse,entity);
    entity.addRelationship(relationship)

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
CoreData.debug = process.env.NOD_ENV isnt 'production'

module.exports = CoreData
