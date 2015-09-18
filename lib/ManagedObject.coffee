ManagedObjectID = require('./ManagedObjectID')

RelationshipDescription = require('./Descriptors/RelationshipDescription')

AttributeValidator = require('./Helpers/AttributeValidator')
AttributeTransformer = require('./Helpers/AttributeTransformer')

ac = require('array-control')
Q = require('q')
async = require('async')

_ = require('underscore');
_.mixin(require('underscore.inflections'));

capitalizedString = (string)->
  string[0].toUpperCase() + string.substring(1);

class ManagedObject extends Object
  constructor:(@entity,@managedObjectContext,@_rawData) ->
    @_objectID = null
    @_isInserted = no
    @_isUpdated = no
    @_isDeleted = no
    @_isFault = yes;
    @_data = null
    @_changes = null
    @_relationChanges = null

  fetchData: ->
    if @_rawData
      data = {}
      for attributeDescription in @entity.attributes
        data[attributeDescription.name] = AttributeTransformer.transformedValueForAttribute(@_rawData[attributeDescription.name],attributeDescription)
      delete @_rawData
      @_data = data
    else
      @_data = @managedObjectContext.storeCoordinator.valuesForObject(this)
    @_isFault = no

  validateValueForKey:(value,key)->
    attributeDescription = @entity.attributesByName()[key]
    AttributeValidator.validateValueForAttribute(value,attributeDescription)

  setValues:(values,allowedAttributes)->
    for attributeDescription in @entity.attributes
      setterFnName = 'set'+capitalizedString(attributeDescription.name)
      if values[attributeDescription.name]? and (not allowedAttributes or attributeDescription.name in allowedAttributes)
        @[setterFnName](values[attributeDescription.name])

  getValues:(options = {})->
    @fetchData() if @isFault
    values = {id:@objectID.recordId()}
    for attributeDescription in @entity.attributes
      getterFnName = 'get'+capitalizedString(attributeDescription.name)
      value = @[getterFnName]()
      if value?
        values[attributeDescription.name] = value
      else
        values[attributeDescription.name] = null
    if not options.noRelations
      for relationship in @entity.relationships
        if not relationship.toMany
          getterFnName = 'get' + capitalizedString(_.singularize(relationship.name)) + 'ID'
          value = @[getterFnName]()
          if value?
            values[_.singularize(relationship.name) + '_id'] = value
          else
            values[_.singularize(relationship.name) + '_id'] = null

    return values

  toJSON:(options)->
    return @getValues(options)

  @addAttributeDescription:(attributeDescription)->
    capitalizedName = capitalizedString(attributeDescription.name);
    @prototype['get' + capitalizedName] = ->
#      console.log('get' + capitalizedName,@isFault)
      @fetchData() if @isFault
      @_data[attributeDescription.name];
    @prototype['set' + capitalizedName] = (value)->
      @fetchData() if @isFault
      if value isnt @_data[attributeDescription.name]
        if value
          @['validate'+capitalizedName](value)
        value = AttributeTransformer.transformedValueForAttribute(value,attributeDescription)
        @_data[attributeDescription.name] = value;
        @_changes = @_changes || {}
        @_changes[attributeDescription.name] = value;
        @_didUpdateValues()
      @
    @prototype['validate'+capitalizedName] = (value)->
      @validateValueForKey(value,attributeDescription.name)
    @bindAttributeDescription(attributeDescription)

  @bindAttributeDescription:(attributeDescription)->
    capitalizedName = attributeDescription.name[0].toUpperCase() + attributeDescription.name.substring(1);
    Object.defineProperty @prototype,attributeDescription.name,
      get: @prototype['get' + capitalizedName]
      set: @prototype['set' + capitalizedName]

  @addRelationshipDescription:(relationshipDescription)->
    singularizedName = _.singularize(relationshipDescription.name)
    capitalizedSingularizedName = singularizedName[0].toUpperCase() + singularizedName.substring(1)
    capitalizedName = relationshipDescription.name[0].toUpperCase() + relationshipDescription.name.substring(1)
    inverseRelationship = relationshipDescription.inverseRelationship()
    inverseRelationshipCapitalizedName = inverseRelationship.name[0].toUpperCase() + inverseRelationship.name.substring(1)
    if not relationshipDescription.toMany
      @prototype['get' + capitalizedSingularizedName + 'ID'] = ()->
        @fetchData() if @isFault
        return @_data[singularizedName + '_id'] or @_data[relationshipDescription.name]?.objectID?.recordId()
      @prototype['get' + capitalizedName] = (callback)->
        deferred = Q.defer()
        @fetchData() if @isFault
        async.nextTick(()=>
          if @_data[relationshipDescription.name] is undefined
            @managedObjectContext._getObjectsForRelationship relationshipDescription,@,@managedObjectContext,(err,object)=>
              if err
                deferred.reject(err)
              else
                deferred.resolve(object)
          else deferred.resolve(@_data[relationshipDescription.name]);
        )
        return deferred.promise.nodeify(callback)
      @prototype['set' + capitalizedName] = (object)->
#        @fetchData() if @isFault
        @_setObjectToRelation(object,relationshipDescription,inverseRelationship)
    else
      @prototype['get' + capitalizedName] = @prototype['get' + capitalizedSingularizedName + 'Objects'] = (callback)->
        deferred = Q.defer()
        @fetchData() if @isFault
        if not @_data[relationshipDescription.name]
          @managedObjectContext._getObjectsForRelationship relationshipDescription,@,@managedObjectContext,(err,objects)=>
            return deferred.reject(err) if err
            if @_relationChanges
              for item in @_relationChanges['added_' + relationshipDescription.name]?
                ac.addObject(objects,item)
              for item in @_relationChanges['removed_' + relationshipDescription.name]?
                ac.removeObject(objects,item)
            @_data[relationshipDescription.name] = objects
            deferred.resolve(@_data[relationshipDescription.name])
        else deferred.resolve(@_data[relationshipDescription.name]);
        return deferred.promise.nodeify(callback)
      @prototype['add' + capitalizedSingularizedName] = (object)->
        @['add' + capitalizedName]([object])
      @prototype['add' + capitalizedName] = @prototype['add' + capitalizedSingularizedName + 'Objects'] = (objects)->
#        @fetchData() if @isFault
        for object in objects
          @_addObjectToRelation(object,relationshipDescription,inverseRelationship)
      @prototype['remove' + capitalizedSingularizedName] = (object)->
        @['remove' + capitalizedName]([object])
      @prototype['remove' + capitalizedName] = @prototype['remove' + capitalizedSingularizedName + 'Objects'] = (objects)->
#        @fetchData() if @isFault
        for object in objects
          @_removeObjectFromRelation(object,relationshipDescription,inverseRelationship)
    @

  prepareForDeletion:(callback)->
    callback()
#    for relationship in @entity.relationships
#      switch relationship.deleteRule
#        when RelationshipDescription.deleteRules.DENY
#          callback(new Error('cannot delete object, relationship deletion denied '+relationship.name))
#        when RelationshipDescription.deleteRules.NULLIFY
#          callback(new Error('nullify not implemented'+relationship.name))
#        when RelationshipDescription.deleteRules.NULLIFY
#          callback(new Error('nullify not implemented'))
#        else callback()


  _setObjectToRelation: (object,relationshipDescription,inversedRelationshipDescription,noRecursion) ->
    @fetchData() if @isFault
    if object isnt @_data[relationshipDescription.name]
      prevObject = @_data[relationshipDescription.name];
      @_data[relationshipDescription.name] = object
      @_relationChanges = @_relationChanges || {}
      @_relationChanges[relationshipDescription.name] = object
      if inversedRelationshipDescription
        if inversedRelationshipDescription.toMany
          if object is null and prevObject
            prevObject._removeObjectFromRelation(@,inversedRelationshipDescription,relationshipDescription,true)
          else if object isnt null
            object._addObjectToRelation(@,inversedRelationshipDescription,relationshipDescription,true)
        else if not noRecursion
          object._setObjectToRelation(@,inversedRelationshipDescription,relationshipDescription,true)

      @_didUpdateValues();


  _addObjectToRelation: (object,relationshipDescription,inversedRelationshipDescription,noRecursion) ->
    @fetchData() if @isFault
    if not @_data[relationshipDescription.name] or object not in @_data[relationshipDescription.name]
      @_relationChanges = @_relationChanges || {}
      @_relationChanges['added_' + relationshipDescription.name] = @_relationChanges['added_' + relationshipDescription.name] || []
      @_relationChanges['removed_' + relationshipDescription.name] = @_relationChanges['removed_' + relationshipDescription.name] || []

      @_data[relationshipDescription.name] = @_data[relationshipDescription.name] or []
      ac.addObject(@_data[relationshipDescription.name],object)

      ac.addObject(@_relationChanges['added_' + relationshipDescription.name],object)
      if @_relationChanges['removed_' + relationshipDescription.name]
        ac.removeObject(@_relationChanges['removed_' + relationshipDescription.name],object)
      if inversedRelationshipDescription and not noRecursion
        if not inversedRelationshipDescription.toMany
          object._setObjectToRelation(@,inversedRelationshipDescription)
        else
          object._addObjectToRelation(@,inversedRelationshipDescription,relationshipDescription,true)
      @_didUpdateValues();

  _removeObjectFromRelation: (object,relationshipDescription,inversedRelationshipDescription,noRecursion,fireEvent = yes) ->
    @fetchData() if @isFault
    if not @_data[relationshipDescription.name] or object in @_data[relationshipDescription.name]
      @_relationChanges = @_relationChanges || {}
      @_relationChanges['added_' + relationshipDescription.name] = @_relationChanges['added_' + relationshipDescription.name] || []
      @_relationChanges['removed_' + relationshipDescription.name] = @_relationChanges['removed_' + relationshipDescription.name] || []
      if @_data[relationshipDescription.name]
        ac.removeObject(@_data[relationshipDescription.name],object)
      ac.addObject(@_relationChanges['removed_' + relationshipDescription.name],object)
      if @_relationChanges['added_' + relationshipDescription.name]
        ac.removeObject(@_relationChanges['added_' + relationshipDescription.name],object)
      if inversedRelationshipDescription and not noRecursion
        if not inversedRelationshipDescription.toMany
          object._setObjectToRelation(null,inversedRelationshipDescription)
        else
          object._removeObjectFromRelation(@,inversedRelationshipDescription,relationshipDescription,true)
      @_didUpdateValues() if fireEvent

  _didUpdateValues: ->
    if @managedObjectContext.locked
      throw new Error('cannot update object when it\'s context is locked')
    @_isUpdated = yes
    if this not in @managedObjectContext?.updatedObjects
      ac.addObject(@managedObjectContext.updatedObjects,this)


  Object.defineProperties @prototype,
    id:
      get: -> @_objectID.recordId()
    objectID:
      get: -> @_objectID
    hasChanges:
      get: -> @isUpdated || @isInserted || @isDeleted
    isInserted:
      get: -> @_isInserted
    isUpdated:
      get: -> @_isUpdated
    isDeleted:
      get: -> @_isDeleted
    isFault:
      get: -> @_isFault

module.exports = ManagedObject;


