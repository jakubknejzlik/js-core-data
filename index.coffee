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


class CoreData
  constructor:(@storeURL,@options = {})->
    if @options.logging is undefined
      @options.logging = console.log
    @model = new ManagedObjectModel(@options.modelFile, @options.modelClasses)

  syncSchema:(options,callback)->
    if typeof options is 'function'
      callback = options
      options = undefined
    options = options or {}
    async.forEach(@_persistentStoreCoordinator().persistentStores,(store,cb)->
      store.syncSchema(options,cb)
    ,callback)

  defineEntity:(entityName,attributes,options = {})->
    entity = new EntityDescription(entityName);
    if options.class
      entity.objectClassName = options.class

    for attributeKey,attributeInfo of attributes
      if attributeInfo not instanceof Object
        attributeInfo = {type:attributeInfo}
      attr = new AttributeDescription(attributeInfo.type,attributeInfo,attributeKey,null);
      if attributeInfo.options
        attr.options = attributeInfo.options
      entity.addAttribute(attr)

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



CoreData.PersistentStoreCoordinator = PersistentStoreCoordinator
CoreData.ManagedObjectModel = ManagedObjectModel
CoreData.ManagedObjectContext = ManagedObjectContext
CoreData.ManagedObject = ManagedObject
CoreData.Predicate = Predicate
CoreData.debug = process.env.NOD_ENV isnt 'production'

module.exports = CoreData

CoreData.createContextPool = (modelFile, storeURL, options, callback) ->

  createAndSendPool = ->
    options = options or {}
    options.name = 'model:' + modelFile + ';store:' + storeURL
    options.max = options.max or 10
    options.idleTimeoutMillis = options.idleTimeoutMillis or 1000

    options.create = (callback) ->
      callback null, new ManagedObjectContext(persistentStoreCoordinator)
      return

    options.destroy = (context) ->
      context.destroy()
      return

    pool = new (Pool.Pool)(options)

    pool.runBlockWithCallback = ((callback, fn) ->
      pool.acquire((err, context) ->
        if err
          return callback(err)
        fn(context, ->
          pool.release(context)
          callback.apply(this, arguments)
        )
      )
    )


    callback null, pool
    return

  options = options or {}
  objectModel = new ManagedObjectModel(modelFile, options.modelClasses)
  persistentStoreCoordinator = new PersistentStoreCoordinator(objectModel)
  if storeURL.indexOf('mysql:') == 0
    persistentStoreCoordinator.addStore(PersistentStoreCoordinator.STORE_TYPE_MYSQL, storeURL, (err) ->
      if err
        return callback(err)
      createAndSendPool()
    )
  else
    callback new Error('unknown store for url' + storeURL)
  return


CoreData.ExpressJS =
  middleware: (contextPool) ->
    (req, res, next) ->
      contextPool.acquire (err, context) ->
        if err
          return next(err)
        req.context = context
        res.on 'finish', ->
          contextPool.release context
          return
        next()
        return
      return
  errorReleaseHandler: (contextPool) ->
    (err, req, res, next) ->
      if req.context
        contextPool.release req.context
      next err
      return
