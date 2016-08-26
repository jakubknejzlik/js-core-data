ManagedObject = require('./ManagedObject')
ManagedObjectID = require('./ManagedObjectID')
FetchRequest = require('./FetchRequest')
Predicate = require('./FetchClasses/Predicate')
SortDescriptor = require('./FetchClasses/SortDescriptor')
RelationshipDescription = require('./Descriptors/RelationshipDescription')
#AttributeTransformer = require('./Helpers/AttributeTransformer')

async = require('async')
ac = require('array-control')
Lock = require('lock')
Promise = require('bluebird')

class ManagedObjectContext extends Object
  constructor:(@storeCoordinator) ->
    @insertedObjects = []
    @updatedObjects = []
    @deletedObjects = []
    @registeredObjects = []
    @locked = no
    @lock = new Lock()
    @destroyed = no

  hasChanges: ->
    return @insertedObjects.length > 0 or @updatedObjects.length > 0 or @deletedObjects.length > 0

  insertObject: (object)->
    if @locked
      throw new Error('context is locked')
    if object.managedObjectContext isnt this
      throw new Error('cannot insert object to another context')
    if object not in @insertedObjects
      object._isFault = no
      values = {}
      for attributeDescription in object.entity.attributes
        defaultValue = attributeDescription.defaultValue()
        if defaultValue isnt null and not attributeDescription.isTransient()
          values[attributeDescription.name] = defaultValue
      object._data = {}
      object.setValues(values,{privates:yes})
      object._isInserted = yes
      object._isDeleted = no
      object._objectID = @storeCoordinator.temporaryObjectID(object)
      ac.addObject(@insertedObjects,object)
      ac.addObject(@registeredObjects,object)
      object.awakeFromInsert()
    ac.removeObject(@deletedObjects,object)

  deleteObject: (object)->
    if @locked
      throw new Error('context is locked')
    @_deleteObjectWithoutLockCheck(object)

  _deleteObjectWithoutLockCheck:(object)->
    if object.managedObjectContext isnt this
      throw new Error('cannot delete object from another context')
    ac.removeObject(@insertedObjects,object)
    #    object._isInserted = no
    object._isDeleted = yes
    ac.addObject(@deletedObjects,object)


  createObjectWithName: (entityName)->
    @storeCoordinator.objectModel.insertObjectIntoContext(entityName,this)

  create:(entityName, data, allowedAttributes)->
    object = @createObjectWithName(entityName)
    object.setValues(data,allowedAttributes)
    return object

  getObjectWithId: (entityName,id,callback)->
    return new Promise((resolve,reject)=>
      async.nextTick(()=>
        entity = @storeCoordinator.objectModel.getEntity(entityName)
        return reject(new Error('entity '+entityName+' not found')) if not entity
        @getObjectWithObjectID(new ManagedObjectID(id,entity)).then(resolve).catch(reject)
      )
    ).asCallback(callback)

  getObjectWithObjectID: (ObjectID,callback)->
    return new Promise((resolve,reject)=>
      request = new FetchRequest(ObjectID.entity)
      request.setLimit(1);
      request.predicate = new Predicate(ObjectID)
      @storeCoordinator.execute(request,@,(err,objects)=>
        return reject(err) if err
        if objects[0]
          ac.addObject(@registeredObjects,objects[0])
          resolve(objects[0])
        else resolve(null)
      )
    ).asCallback(callback)

  getObjects: (entityName,options,callback)->
    if typeof options is 'function'
      callback = options
      options = undefined
    return new Promise((resolve,reject)=>
      @storeCoordinator.execute(@_getFetchRequest(entityName,options),@,(err,objects)=>
        if err
          reject(err)
        else
          ac.addObjects(@registeredObjects,objects)
          resolve(objects)
      )
    ).asCallback(callback)

  fetch: (entityName,options,callback)->
    if typeof options is 'function'
      callback = options
      options = undefined
    return new Promise((resolve,reject)=>
      request = @_getFetchRequest(entityName,options)
      request.resultType = FetchRequest.RESULT_TYPE.VALUES
      @storeCoordinator.execute(request,@,(err,values)=>
        if err
          reject(err)
        else
          resolve(values)
      )
    ).asCallback(callback)

  _getFetchRequest:(entityName,options)->
    options = options or {}
    predicate = null
    havingPredicate = null
    sortDescriptors = []

    if typeof options.where is 'string'
      predicate = new Predicate(options.where)
    else if Array.isArray(options.where)
      where = options.where.slice()
      where.unshift(null)
      predicate = new (Function.prototype.bind.apply(Predicate, where))
    else if typeof options.where is 'object'
      predicate = new Predicate(options.where)

    if typeof options.having is 'string'
      havingPredicate = new Predicate(options.having)
    else if Array.isArray(options.having)
      having = options.having.slice()
      having.unshift(null)
      havingPredicate = new (Function.prototype.bind.apply(Predicate, having))
    else if typeof options.having is 'object'
      havingPredicate = new Predicate(options.having)

    sort = options.sort or options.order
    if typeof sort is 'string'
      sort = [sort]
    if Array.isArray(sort)
      for sortItem in sort
        ascending = yes
        if sortItem[0] is '-'
          ascending = no
          sortItem = sortItem.substring(1)
        sortDescriptors.push(new SortDescriptor(sortItem,ascending))


    request = new FetchRequest(@storeCoordinator.objectModel.getEntity(entityName),predicate,sortDescriptors)
    request.predicate = predicate
    request.havingPredicate = havingPredicate
    request.sortDescriptors = sortDescriptors

    if options.offset and not options.limit
      throw new Error('limit must be supplied when fetching with offset')

    request.setLimit(options.limit) if options.limit
    request.setOffset(options.offset) if options.offset

    request.fields = options.fields
    request.group = options.group

    return request

  getObject: (entityName,options,callback)->
    if typeof options is 'function'
      callback = options
      options = null
    return new Promise((resolve,reject)=>
      options = options or {}
      options.limit = 1
      @getObjects(entityName,options).then((objects)->
        if objects.length > 0
          resolve(objects[0])
        else
          resolve(null)
      ).catch(reject)
    ).asCallback(callback)

  getOrCreateObject:(entityName,options,defaultValues,callback)->
    if typeof defaultValues is 'function'
      callback = defaultValues
      defaultValues = undefined
    return new Promise((resolve,reject)=>
      @lock(entityName,(release)=>
  #      callback = release(callback)
        @getObject(entityName,options,(err,object)=>
          if err
            release()()
            return reject(err)
          if not object
            object = @create(entityName,defaultValues)
          resolve(object)
          release()()
        )
      )
    ).asCallback(callback)

  getObjectsCount:(entityName,options,callback)->
    if typeof options is 'function'
      callback = options
      options = undefined
    return new Promise((resolve,reject)=>
      @storeCoordinator.numberOfObjectsForFetchRequest(@_getFetchRequest(entityName,options),(err,count)->
        if err
          reject(err)
        else
          resolve(count)
      )
    ).asCallback(callback)



  _getObjectsForRelationship: (relationship,object,context,callback)->
    if object.objectID.isTemporaryID
      return callback(null,[])
    @storeCoordinator._valuesForForRelationship relationship,object.objectID,context,(err,objects)=>
      return callback(err) if err
      ac.addObjects(@registeredObjects,objects)
      callback(null,objects)



  saveAndDestroy:(callback)->
    promise = @save().then(()=>
      @destroy()
      callback() if callback
    )
    promise.catch(callback) if callback

  save: (callback)->
    return new Promise((resolve,reject)=>
      if @locked
        throw new Error('context is locked')

      allObjects = []
      for obj in @insertedObjects.concat(@updatedObjects,@deletedObjects)
        if obj not in allObjects
          allObjects.push(obj)
      for obj in allObjects
        obj.willSave()


      @locked = yes
      async.nextTick(()=>
        if not @hasChanges
          @locked = no
          return resolve()
        #    console.log('has changes');

        @_processDeletedObjects((err)=>
          if err
            @locked = no
            return reject(err);
          @storeCoordinator.saveContext(@,(err)=>
            if not err
              for object in @insertedObjects
                object._changes = null
                object._relationChanges = null
                object._isInserted = no
              for object in @updatedObjects
                object._changes = null
                object._relationChanges = null
                object._isUpdated = no
              for object in @deletedObjects
                object._isDeleted = no
              @insertedObjects = []
              @updatedObjects = []
              @deletedObjects = []
            @locked = no
            if err
              reject(err)
            else
              for obj in allObjects
                obj.didSave()
              resolve()
          )
        )
      )
    ).asCallback(callback)

  reset:->
    if @locked
      throw new Error('context is locked')
    @registeredObjects = []
    @updatedObjects = []
    @deletedObjects = []

  destroy: ->
    if @destroyed
      throw new Error('destroying already destroyed context')
    if @locked
      throw new Error('context is locked')
    @destroyed = yes
    delete @registeredObjects
    delete @insertedObjects
    delete @updatedObjects
    delete @deletedObjects
    delete @storeCoordinator

  Object.defineProperties @prototype,
    hasChanges:
      get: @prototype.hasChanges


  _processDeletedObjects:(callback)->
    async.forEach @deletedObjects,(object,cb)=>
      object.prepareForDeletion(cb)
    ,callback


  _didUpdateObject:(object)->
    if @destroyed
      throw new Error('updating values on object on destroyed context')
    if @locked
      throw new Error('cannot update object when it\'s context is locked')
    if object not in @updatedObjects
      ac.addObject(@updatedObjects,object)


module.exports = ManagedObjectContext;