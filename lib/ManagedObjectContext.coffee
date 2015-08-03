async = require('async')
ManagedObject = require('./ManagedObject')
ManagedObjectID = require('./ManagedObjectID')
FetchRequest = require('./FetchRequest')
Predicate = require('./FetchClasses/Predicate')
RelationshipDescription = require('./Descriptors/RelationshipDescription')

ac = require('array-control')

class ManagedObjectContext extends Object
  constructor:(@storeCoordinator) ->
    @insertedObjects = []
    @updatedObjects = []
    @deletedObjects = []
    @registeredObjects = []
    @locked = no

  hasChanges: ->
    return @insertedObjects.length > 0 or @updatedObjects.length > 0 or @deletedObjects.length > 0

  insertObject: (object)->
    if @locked
      throw new Error('context is locked')
    if object.managedObjectContext isnt this
      throw new Error('cannot insert object to another context')
    if object not in @insertedObjects
      object._isFault = no
      object._data = {}
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
    object._isInserted = no
    object._isDeleted = yes
    ac.addObject(@deletedObjects,object)


  createObjectWithName: (entityName)->
    @storeCoordinator.objectModel.insertObjectIntoContext(entityName,this)

  getObjectWithId: (entityName,id,callback)->
    entity = @storeCoordinator.objectModel.getEntity(entityName)
    return callback(new Error('entity '+entityName+' not found')) if not entity
    @getObjectWithObjectID(new ManagedObjectID(id,entity),callback)

  getObjectWithObjectID: (ObjectID,callback)->
#    cache?!
    request = new FetchRequest(ObjectID.entity)
    request.setLimit(1);
    request.predicate = new Predicate(ObjectID)
#    console.log('execute request');
    @storeCoordinator.execute request,this,(err,objects)=>
      return callback(err) if err
      if objects[0]
        ac.addObject(@registeredObjects,objects[0])
        callback(null,objects[0])
      else callback(null,null)

  getObjects: (entityName,predicate,sortDescriptors,callback)->
#    cache?!
    request = new FetchRequest(@storeCoordinator.objectModel.getEntity(entityName),predicate,sortDescriptors)
    request.predicate = predicate
    request.sortDescriptors = sortDescriptors
    @storeCoordinator.execute request,this,(err,objects)=>
      if not err
        ac.addObjects(@registeredObjects,objects)
      callback(err,objects)

  getObject: (entityName,predicate,callback)->
    @getObjects entityName,predicate,null,(err,objects)->
      return callback(err) if err
      if objects.length > 0
        callback(null,objects[0])
      else
        callback(null,null)

  _getObjectsForRelationship: (relationship,object,context,callback)->
    if object.objectID.isTemporaryID
      return callback(null,[])
    @storeCoordinator._valuesForForRelationship relationship,object.objectID,context,(err,objects)->
#      console.log('!!!!',objects,object)
      callback(err,objects)


  save: (callback)->
#    console.log('saving')
    if @locked
      throw new Error('context is locked')
    return callback(null) if not @hasChanges
    @locked = yes
#    console.log('has changes');

    @_processDeletedObjects (err)=>
      if err
        @locked = no
        return callback(err);
      @storeCoordinator.saveContext @,(err)=>
  #      console.log('done saving',err)
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
        callback(err)

  reset:->
    if @locked
      throw new Error('context is locked')
    @registeredObjects = []
    @updatedObjects = []
    @deletedObjects = []

  destroy: ->
    if @locked
      throw new Error('context is locked')
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
                  object._removeObjectFromRelation(obj,relationship,relationship.inverseRelationship(),yes)
                  obj._removeObjectFromRelation(object,relationship.inverseRelationship(),relationship,yes)
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


module.exports = ManagedObjectContext;