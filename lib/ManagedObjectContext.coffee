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
Q = require('q')

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
        values[attributeDescription.name] = attributeDescription.defaultValue()
      object._data = {}
      object.setValues(values)
      object._isInserted = yes
      object._isDeleted = no
      object._objectID = @storeCoordinator.temporaryObjectID(object)
      ac.addObject(@insertedObjects,object)
      ac.addObject(@registeredObjects,object)
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
    deferred = Q.defer()
    async.nextTick(()=>
      entity = @storeCoordinator.objectModel.getEntity(entityName)
      return deferred.reject(new Error('entity '+entityName+' not found')) if not entity
      @getObjectWithObjectID(new ManagedObjectID(id,entity)).then(deferred.resolve).catch(deferred.reject)
    )
    return deferred.promise.nodeify(callback)

  getObjectWithObjectID: (ObjectID,callback)->
    deferred = Q.defer()
    request = new FetchRequest(ObjectID.entity)
    request.setLimit(1);
    request.predicate = new Predicate(ObjectID)
    @storeCoordinator.execute(request,@,(err,objects)=>
      return deferred.reject(err) if err
      if objects[0]
        ac.addObject(@registeredObjects,objects[0])
        deferred.resolve(objects[0])
      else deferred.resolve(null)
    )
    return deferred.promise.nodeify(callback)

  getObjects: (entityName,options,callback)->
    deferred = Q.defer()
    if typeof options is 'function'
      callback = options
      options = undefined

    @storeCoordinator.execute(@_getFetchRequest(entityName,options),@,(err,objects)=>
      if err
        deferred.reject(err)
      else
        ac.addObjects(@registeredObjects,objects)
        deferred.resolve(objects)
    )
    return deferred.promise.nodeify(callback)

  fetch: (entityName,options,callback)->
    deferred = Q.defer()
    if typeof options is 'function'
      callback = options
      options = undefined

    request = @_getFetchRequest(entityName,options)
    request.resultType = FetchRequest.RESULT_TYPE.VALUES
    @storeCoordinator.execute(request,@,(err,values)=>
      if err
        deferred.reject(err)
      else
        deferred.resolve(values)
    )
    return deferred.promise.nodeify(callback)

  _getFetchRequest:(entityName,options)->
    options = options or {}
    predicate = null
    sortDescriptors = []

    if typeof options.where is 'string'
      predicate = new Predicate(options.where)
    else if Array.isArray(options.where)
      where = options.where.slice()
      where.unshift(null)
      predicate = new (Function.prototype.bind.apply(Predicate, where))

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
    request.sortDescriptors = sortDescriptors

    if options.offset and not options.limit
      throw new Error('limit must be supplied when fetching with offset')

    request.setLimit(options.limit) if options.limit
    request.setOffset(options.offset) if options.offset

    request.fields = options.fields
    request.group = options.group

    return request

  getObject: (entityName,options,callback)->
    deferred = Q.defer()
    if typeof options is 'function'
      callback = options
      options = null
    options = options or {}
    options.limit = 1
    @getObjects(entityName,options).then((objects)->
      if objects.length > 0
        deferred.resolve(objects[0])
      else
        deferred.resolve(null)
    ).catch(deferred.reject)
    return deferred.promise.nodeify(callback)

  getOrCreateObject:(entityName,options,defaultValues,callback)->
    deferred = Q.defer()
    if typeof defaultValues is 'function'
      callback = defaultValues
      defaultValues = undefined
    @lock(entityName,(release)=>
#      callback = release(callback)
      @getObject(entityName,options,(err,object)=>
        if err
          release()()
          return deferred.reject(err)
        if not object
          object = @create(entityName,defaultValues)
        deferred.resolve(object)
        release()()
      )
    )
    return deferred.promise.nodeify(callback)

  getObjectsCount:(entityName,options,callback)->
    deferred = Q.defer()
    if typeof options is 'function'
      callback = options
      options = undefined

    @storeCoordinator.numberOfObjectsForFetchRequest(@_getFetchRequest(entityName,options),(err,count)->
      if err
        deferred.reject(err)
      else
        deferred.resolve(count)
    )
    return deferred.promise.nodeify(callback)



  _getObjectsForRelationship: (relationship,object,context,callback)->
    if object.objectID.isTemporaryID
      return callback(null,[])
    @storeCoordinator._valuesForForRelationship relationship,object.objectID,context,(err,objects)->
#      console.log('!!!!',objects,object)
      callback(err,objects)




  saveAndDestroy:(callback)->
    @save().then(()=>
      @destroy()
      callback() if callback
    ).catch(callback)

  save: (callback)->
    deferred = Q.defer()
#    callback = callback or (err)->
#      throw err if err
#    console.log('saving')
    if @locked
      throw new Error('context is locked')
    @locked = yes
    async.nextTick(()=>
      if not @hasChanges
        @locked = no
        return deferred.resolve()
  #    console.log('has changes');

      @_processDeletedObjects((err)=>
        if err
          @locked = no
          return deferred.reject(err);
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
            deferred.reject(err)
          else
            deferred.resolve()
        )
      )
    )
    return deferred.promise.nodeify(callback)

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
      ,(err)=>
        if err
          return callback(err)
        dels = []
        for obj in @deletedObjects
          dels.push(obj)
        async.forEach dels,(object,cb)=>
            @_deleteObjectsRelationships(object,cb)
          ,callback



  _deleteObjectsRelationships:(object,callback)->
    async.forEach object.entity.relationships,(relationship,cb)=>
        switch relationship.deleteRule
          when RelationshipDescription.deleteRules.DENY
            @_getObjectsForRelationship relationship,object,@,(err,objects)->
              return cb(err) if err
              canDelete = yes
              if objects.length > 0
                for obj in objects
                  canDelete = canDelete and obj.isDeleted
              else canDelete = yes
              if not canDelete
                return cb(new Error('cannot delete object, deletion denied for relationship '+relationship.entity.name+'->'+relationship.name))
              else return cb()
          when RelationshipDescription.deleteRules.NULLIFY
            @_getObjectsForRelationship relationship,object,@,(err,objects)=>
              return cb(err) if err
              if objects
                for obj in objects
#                  console.log('remove',obj.objectID.toString(),'=>',relationship.name)
                  object._removeObjectFromRelation(obj,relationship,relationship.inverseRelationship(),yes,no)
                  obj._removeObjectFromRelation(object,relationship.inverseRelationship(),relationship,yes,no)
              cb()
          when RelationshipDescription.deleteRules.CASCADE
#            console.log('cascade')
            @_getObjectsForRelationship relationship,object,@,(err,objects)=>
              return cb(err) if err
              if objects
                async.forEach objects,(obj,_cb)=>
                  @_deleteObjectWithoutLockCheck(obj)
                  @_deleteObjectsRelationships(obj,_cb)
                ,cb
              else cb()
          else return cb(new Error('not implemented ' + relationship.deleteRule))
      ,callback

  _didUpdateObject:(object)->
    if @destroyed
      throw new Error('updating values on object on destroyed context')
    if @locked
      throw new Error('cannot update object when it\'s context is locked')
    if object not in @updatedObjects
      ac.addObject(@updatedObjects,object)


module.exports = ManagedObjectContext;