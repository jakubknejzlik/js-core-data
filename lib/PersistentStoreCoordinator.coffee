PersistentStoreRequest = require('./stores/PersistentStoreRequest')
IncrementalStore = require('./stores/IncrementalStore')
ManagedObject = require('./ManagedObject')
Predicate = require('./FetchClasses/Predicate')
#AttributeTransformer = require('./Helpers/AttributeTransformer')
FetchRequest = require('./FetchRequest')
async = require('async')
url = require('url')
ac = require('array-control')

_knownStoreProtocols = {
  'sqlite:':'SQLiteStore',
  'mysql:':'MySQLStore',
  'postgres:':'PostgreSQLStore'
}

class PersistentStoreCoordinator extends Object
  @STORE_TYPE_MYSQL = 'MySQLStore'
  @STORE_TYPE_SQLITE = 'SQLiteStore'
  @STORE_TYPE_POSTGRES = 'PostgreSQLStore'

  registeredStoreTypes = {}

  constructor: (@objectModel,@globals = {})->
#    @store = new storeClasses[storeType]
    throw new Error('Cannot create coordinator without object model') if not @objectModel
    @persistentStores = []
    @waitingRequests = []
    @temporaryId = 1
    @parallelExecution = yes



  @registerStoreClass: (storeClass,storeType)->
    registeredStoreTypes[storeType] = storeClass
    this

  addStore: (storeTypeOrStore,URL,callback)->
    store = null
    if storeTypeOrStore instanceof IncrementalStore
      store = storeTypeOrStore
    else
      if URL is undefined
        URL = storeTypeOrStore
        parsedURL = url.parse(URL)
        storeTypeOrStore = _knownStoreProtocols[parsedURL.protocol]
      if not storeTypeOrStore
        throw new Error('unknown store for url ' + URL)
      storeClass = registeredStoreTypes[storeTypeOrStore]
      if not storeClass
        storeClass = require('./stores/Defaults/'+storeTypeOrStore)
      store = new (storeClass)(this,URL,@globals);

    if not store
      throw new Error('could not identify store')
    if callback
      console.error('adding store with callback is deprecated')
      store.syncSchema((err)=>
        if not err
          @persistentStores.push(store)
        callback(err) if callback
      )
    else
      @persistentStores.push(store)

  execute: (request,context,callback)->
    @waitingRequests.push({request:request,context:context,callback:callback});
    @_executeNextRequestIfPossible()

  _executeNextRequestIfPossible: ()->
    if @executingRequest and not @parallelExecution
      return
    info = @waitingRequests.shift()

    #    console.log('next info',info);
    if not info
      return

    @executingRequest = true

    request = info.request
    context = info.context
    callback = info.callback

    if request.type is 'fetch' and request.predicate?.isObjectIDPredicate()
      obj = @_objectFromContextCache(context,request.predicate.objectID())
      if obj
        return @_requestCompleted(callback,null,[obj])

    store = @persistentStores[0]
    store.execute(request,context,(err,ObjectIDsOrValues,objectValues = {})=>
      return @_requestCompleted(callback,err) if err
      if request.resultType is FetchRequest.RESULT_TYPE.VALUES
        return callback(null,ObjectIDsOrValues)
      objects = []
      for objectID in ObjectIDsOrValues
        obj = @_objectFromContextCache(context,objectID)
        if obj
          objects.push(obj)
        else
          objects.push(@_objectForID(request.entity,context,objectID,objectValues[objectID.toString()]))
      @_requestCompleted(callback,null,objects)
    )

  numberOfObjectsForFetchRequest:(request,callback)->
    store = @persistentStores[0]
    store.numberOfObjectsForFetchRequest(request,callback)

  _requestCompleted:(callback,err,objects)->
    @executingRequest = false
    callback(err,objects)
    @_executeNextRequestIfPossible()


  _objectForID: (entity,context,objectID,objectValues = {}) ->
    subclass = @objectModel.subclassForEntity(entity.name);
    object = new subclass(entity,context,objectValues)
    object._objectID = objectID
    object.awakeFromFetch()
    return object

  _objectFromContextCache: (context,objectID)->
    if not context.registeredObjects
      return null
    for object in context.registeredObjects
      if object.objectID.isEqual(objectID)
        return object
    return null


  saveContext: (context,callback)->
#    incremental store only
    request = new PersistentStoreRequest('save')
    request.insertedObjects = context.insertedObjects
    request.updatedObjects = []
    for obj in context.updatedObjects
      if not ac.hasObject(request.insertedObjects,obj)
        request.updatedObjects.push(obj)
    request.deletedObjects = context.deletedObjects
    temporaryObjectIDs = []

    async.forEach(@persistentStores,
    (store,cb)->
      if store instanceof IncrementalStore
        store.execute(request,context,(err)->
          if err
            for i,object of context.insertedObjects
              object._objectID = temporaryObjectIDs[i]
          cb(err)
        ,()=>
          permanentObjectIDs = store.permanentIDsForObjects(context.insertedObjects)
          for i,object of context.insertedObjects
            temporaryObjectIDs[i] = object._objectID
            object._objectID = permanentObjectIDs[i]
        )
      else cb(new Error('not an incremental store'))
    ,(err)=>
      callback(err)
    )

  _valuesForForRelationship: (relationship,ObjectID,context,callback)->
    inversedRelationship = relationship.inverseRelationship()
    request = new FetchRequest(inversedRelationship.entity,new Predicate('SELF.' + inversedRelationship.name + '._id = %d',ObjectID.recordId()))
    @execute(request,context,callback)
#    store = @persistentStores[0]
#    store.valuesForRelationship relationship,ObjectID,context,(err,ObjectIDs)=>
#      return callback(err) if err
#      if relationship.toMany
#        objects = []
#        for objID in ObjectIDs
#          object = @_objectFromContextCache(context,objID)
#          if not object
#            subclass = @objectModel.subclassForEntity(relationship.destinationEntity.name);
#            object = new subclass(relationship.destinationEntity,context)
#            object._objectID = objID
#          ac.addObject(objects,object)
#        callback(null,objects)
#      else
#        if not ObjectIDs
#          return callback(null,null)
#        object = @_objectFromContextCache(context,ObjectIDs)
#        if not object
#          subclass = @objectModel.subclassForEntity(relationship.destinationEntity.name);
#          object = new subclass(relationship.destinationEntity,context)
#          object._objectID = ObjectIDs
#        callback(null,object)

  temporaryObjectID: (object)->
    id = @persistentStores[0].newObjectID(object.entity,@temporaryId++)
    id.isTemporaryID = yes
    id

#  valuesForObject: (object)->
#    values = @persistentStores[0].valuesForObject(object.objectID,object.context)
#    for attribute in object.entity.attributes
#      values[attribute.name] = attribute.transform(values[attribute.name],attribute)
#    values


  Object.defineProperties @prototype,
    registeredStoreTypes:
      get: -> registeredStoreTypes

# If a relationship is nil, you should create a new value by invoking newValueForRelationship:forObjectWithID:withContext:error: on the NSPersistentStore object.

#PersistentStoreCoordinator.registerStoreClass(require('./stores/Defaults/MySQLStore'),PersistentStoreCoordinator.STORE_TYPE_MYSQL);
#PersistentStoreCoordinator.registerStoreClass(require('./stores/Defaults/SQLiteStore'),PersistentStoreCoordinator.STORE_TYPE_SQLITE);

module.exports = PersistentStoreCoordinator;
