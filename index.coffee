PersistentStoreCoordinator = require('./lib/PersistentStoreCoordinator')
ManagedObjectModel = require('./lib/ManagedObjectModel')
ManagedObjectContext = require('./lib/ManagedObjectContext')
ManagedObject = require('./lib/ManagedObject')
Predicate = require('./lib/FetchClasses/Predicate')
Pool = require('generic-pool')
module.exports.PersistentStoreCoordinator = PersistentStoreCoordinator
module.exports.ManagedObjectModel = ManagedObjectModel
module.exports.ManagedObjectContext = ManagedObjectContext
module.exports.ManagedObject = ManagedObject
module.exports.Predicate = Predicate
module.exports.debug = false



module.exports.createContextPool = (modelFile, storeURL, options, callback) ->

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


module.exports.ExpressJS =
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
