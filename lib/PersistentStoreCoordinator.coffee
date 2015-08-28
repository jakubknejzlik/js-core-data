PersistentStoreRequest = require('./stores/PersistentStoreRequest')
IncrementalStore = require('./stores/IncrementalStore')
ManagedObject = require('./ManagedObject')
Predicate = require('./FetchClasses/Predicate')
AttributeTransformer = require('./Helpers/AttributeTransformer')
async = require('async')
url = require('url')
ac = require('array-control')

_knownStoreProtocols = {
  'sqlite:':'SQLiteStore',
  'mysql:':'MySQLStore'
}

class PersistentStoreCoordinator extends Object
  @STORE_TYPE_MYSQL = 'MySQLStore'
  @STORE_TYPE_SQLITE = 'SQLiteStore'

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

  addStore: (storeType,URL,callback)->
    if URL is undefined
      URL = storeType
      parsedURL = url.parse(URL)
      storeType = _knownStoreProtocols[parsedURL.protocol]
    if not storeType
      throw new Error('unknown store for url ' + URL)
    storeClass = registeredStoreTypes[storeType]
    if not storeClass
      storeClass = require('./stores/Defaults/'+storeType)
    store = new (storeClass)(this,URL,@globals);
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
    store.execute(request,context,(err,ObjectIDsOrCount)=>
      return @_requestCompleted(callback,err) if err
      objects = []
      for objectID in ObjectIDsOrCount
        obj = @_objectFromContextCache(context,objectID)
        if obj
          objects.push(obj)
        else
          objects.push(@_objectForID(request,context,objectID))
      @_requestCompleted(callback,null,objects)
    )

  numberOfObjectsForFetchRequest:(request,callback)->
    store = @persistentStores[0]
    store.numberOfObjectsForFetchRequest(request,callback)

  _requestCompleted:(callback,err,objects)->
    @executingRequest = false
    callback(err,objects)
    @_executeNextRequestIfPossible()


  _objectForID: (request,context,objectID) ->
    subclass = @objectModel.subclassForEntity(request.entity.name);
    object = new subclass(request.entity,context)
    object._objectID = objectID
    return object

  _objectFromContextCache: (context,objectID)->
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
    store = @persistentStores[0]
    store.valuesForRelationship relationship,ObjectID,context,(err,ObjectIDs)=>
      return callback(err) if err
      if relationship.toMany
        objects = []
        for objID in ObjectIDs
          object = @_objectFromContextCache(context,objID)
          if not object
            subclass = @objectModel.subclassForEntity(relationship.destinationEntity.name);
            object = new subclass(relationship.destinationEntity,context)
            object._objectID = objID
          ac.addObject(objects,object)
        callback(null,objects)
      else
        if not ObjectIDs
          return callback(null,null)
        object = @_objectFromContextCache(context,ObjectIDs)
        if not object
          subclass = @objectModel.subclassForEntity(relationship.destinationEntity.name);
          object = new subclass(relationship.destinationEntity,context)
          object._objectID = ObjectIDs
        callback(null,object)

  temporaryObjectID: (object)->
    id = @persistentStores[0].newObjectID(object.entity,@temporaryId++)
    id.isTemporaryID = yes
    id

  valuesForObject: (object)->
    values = @persistentStores[0].valuesForObject(object.objectID,object.context)
    for attributeDescription in object.entity.attributes
      values[attributeDescription.name] = AttributeTransformer.transformedValueForAttribute(values[attributeDescription.name],attributeDescription)
    values


  Object.defineProperties @prototype,
    registeredStoreTypes:
      get: -> registeredStoreTypes

# If a relationship is nil, you should create a new value by invoking newValueForRelationship:forObjectWithID:withContext:error: on the NSPersistentStore object.

#PersistentStoreCoordinator.registerStoreClass(require('./stores/Defaults/MySQLStore'),PersistentStoreCoordinator.STORE_TYPE_MYSQL);
#PersistentStoreCoordinator.registerStoreClass(require('./stores/Defaults/SQLiteStore'),PersistentStoreCoordinator.STORE_TYPE_SQLITE);

module.exports = PersistentStoreCoordinator;