ManagedObjectID = require('./ManagedObjectID')

RelationshipDescription = require('./Descriptors/RelationshipDescription')

AttributeValidator = require('./Helpers/AttributeValidator')
AttributeTransformer = require('./Helpers/AttributeTransformer')

ac = require('array-control')

_ = require('underscore');
_.mixin(require('underscore.inflections'));

capitalizedString = (string)->
  string[0].toUpperCase() + string.substring(1);

class ManagedObject extends Object
  constructor:(@entity,@managedObjectContext) ->
    @_objectID = null
    @_isInserted = no
    @_isUpdated = no
    @_isDeleted = no
    @_isFault = yes;
    @_data = null
    @_changes = null
    @_relationChanges = null

  fetchData: ->
    @_data = @managedObjectContext.storeCoordinator.valuesForObject(this)
    @_isFault = no
#    console.log('fetched data',@_data)

  validateValueForKey:(value,key)->
    attributeDescription = @entity.attributesByName()[key]
    AttributeValidator.validateValueForAttribute(value,attributeDescription)

  setValues:(values)->
    for attributeDescription in @entity.attributes
      setterFnName = 'set'+capitalizedString(attributeDescription.name)
#      console.log(setterFnName,@[setterFnName])
      if values[attributeDescription.name]?
#        console.log('set',setterFnName,values[attributeDescription.name],values)
        @[setterFnName](values[attributeDescription.name])

  getValues:->
    @fetchData() if @isFault
    values = {id:parseInt(@objectID.recordId())}
    for attributeDescription in @entity.attributes
      getterFnName = 'get'+capitalizedString(attributeDescription.name)
#      console.log(getterFnName,@[getterFnName])
      value = @[getterFnName]()
      if value?
        values[attributeDescription.name] = value
      else
        values[attributeDescription.name] = null
    return values

  toJSON:->
    return @getValues()

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
        value = AttributeTransformer.transformValueForAttribute(value,attributeDescription)
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
      @prototype['get' + capitalizedName] = (callback)->
        @fetchData() if @isFault
        if @_data[relationshipDescription.name] is undefined
#          console.log('getting!',@_data[relationshipDescription.name])
          @managedObjectContext._getObjectsForRelationship relationshipDescription,@,@managedObjectContext,(err,object)=>
#            console.log('got!',@_data[relationshipDescription.name])
            callback(err,object)
        else callback(null,@_data[relationshipDescription.name]);
      @prototype['set' + capitalizedName] = (object)->
#        console.log('set',capitalizedName,object)
#        @fetchData() if @isFault
        @_setObjectToRelation(object,relationshipDescription,inverseRelationship)
    else
#      console.log('add' + capitalizedSingularizedName)
#      console.log('add' + capitalizedName + 'Objects')
#      console.log('get' + capitalizedName + 'Objects')
      @prototype['get' + capitalizedName] = @prototype['get' + capitalizedSingularizedName + 'Objects'] = (callback)->
        @fetchData() if @isFault
        if not @_data[relationshipDescription.name]
#          console.log('get',capitalizedName,@_data[relationshipDescription.name])
          @managedObjectContext._getObjectsForRelationship relationshipDescription,@,@managedObjectContext,(err,objects)=>
            return callback(err) if err
#            console.log('got objects',objects.length)
            if @_relationChanges
              for item in @_relationChanges['added_' + relationshipDescription.name]?
                ac.addObject(objects,item)
              for item in @_relationChanges['removed_' + relationshipDescription.name]?
#                for subitem in objects
#                  console.log('removing objects',item.objectID.toString() ,subitem.objectID.toString(),item == subitem)
                ac.removeObject(objects,item)
            @_data[relationshipDescription.name] = objects
            callback(null,@_data[relationshipDescription.name])
        else callback(null,@_data[relationshipDescription.name]);
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
#    console.log('set',relationshipDescription.name)
    if object isnt @_data[relationshipDescription.name]
#      console.log('settings object',object)
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
#      console.log('adding xxx',relationshipDescription.name,inversedRelationshipDescription?.name);
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
#      console.log('add',@objectID.toString());
      @_didUpdateValues();

  _removeObjectFromRelation: (object,relationshipDescription,inversedRelationshipDescription,noRecursion) ->
    @fetchData() if @isFault
#    console.log('remove',object.objectID.toString(),relationshipDescription.name,'=>',inversedRelationshipDescription.name)
    if not @_data[relationshipDescription.name] or object in @_data[relationshipDescription.name]
      @_relationChanges = @_relationChanges || {}
#      console.log('remove',@_data,@objectID.toString());
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
      @_didUpdateValues();

  _didUpdateValues: ->
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


