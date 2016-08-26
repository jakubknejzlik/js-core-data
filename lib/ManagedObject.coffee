ManagedObjectID = require('./ManagedObjectID')

RelationshipDescription = require('./Descriptors/RelationshipDescription')

ac = require('array-control')
Promise = require('bluebird')
async = require('async')
util = require('util')

_ = require('underscore');
_.mixin(require('underscore.inflections'));

capitalizedString = (string)->
  string[0].toUpperCase() + string.substring(1);

class ManagedObject extends Object
  constructor:(@entity,@managedObjectContext,@_rawData) ->
    @context = @managedObjectContext
    @_objectID = null
    @_isInserted = no
#    @_isUpdated = no
    @_isDeleted = no
    @_isFault = yes;
    @_data = null
    @_changes = null
    @_relationChanges = null

  fetchData: ->
    data = {}
    if @_rawData
      for attribute in @entity.attributes
        data[attribute.name] = attribute.transform(@_rawData[attribute.name])
      for relationship in @entity.relationships
        data[relationship.name + '_id'] = @_rawData[relationship.name + '_id']
    delete @_rawData
    @_data = data
    @_isFault = no

  validateValueForKey:(value,key)->
    attributeDescription = @entity.attributesByName()[key]
    attributeDescription.validateValue(value)

  setValues:(values = {},allowedAttributes,options = {})->
    if not Array.isArray(allowedAttributes)
      options = allowedAttributes or {}
      allowedAttributes = null
    for attributeDescription in @entity.attributes
      if (values[attributeDescription.name] isnt undefined) and (not allowedAttributes or attributeDescription.name in allowedAttributes) and (not attributeDescription.isPrivate() or options.privates or (allowedAttributes and attributeDescription.name in allowedAttributes))
        @[attributeDescription.name] = values[attributeDescription.name]

  getValues:(allowedAttributes,options = {})->
    if not Array.isArray(allowedAttributes)
      options = allowedAttributes or {}
      allowedAttributes = options.attributes or null
    @fetchData() if @isFault
    values = {id:@objectID.recordId()}
    for attributeDescription in @entity.attributes
      if (not allowedAttributes or attributeDescription.name in allowedAttributes) and (not attributeDescription.isPrivate() or options.privates)
        value = @[attributeDescription.name]
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

    if not attributeDescription.isTransient()
      @prototype['get' + capitalizedName] = @prototype['get' + capitalizedName] or ()->
          return @['_get' + capitalizedName]()
      @prototype['set' + capitalizedName] = @prototype['set' + capitalizedName] or (value)->
          return @['_set' + capitalizedName](value)

      @prototype['_get' + capitalizedName] = ->
        @fetchData() if @isFault
        value = @_data[attributeDescription.name]
        if value is undefined
          return null
        return value
      @prototype['_set' + capitalizedName] = (value)->
        @fetchData() if @isFault
        if value isnt @_data[attributeDescription.name]
          if typeof @['validate'+capitalizedName] is 'function'
            if not @['validate'+capitalizedName](value)
              throw new Error('value \''+value+'\' ('+(typeof value)+') is not valid for attribute ' + attributeDescription.name)
          @['_validate'+capitalizedName](value)
          value = attributeDescription.transform(value)
          @_data[attributeDescription.name] = value;
          @_changes = @_changes || {}
          @_changes[attributeDescription.name] = value;
          @_didUpdateValues()
        @
      @prototype['_validate'+capitalizedName] = (value)->
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
      @prototype['get' + capitalizedName ] = @prototype['get' + capitalizedName] or (callback)->
          return @['_get' + capitalizedName ](callback)
      @prototype['set' + capitalizedName ] = @prototype['set' + capitalizedName] or (object)->
          return @['_set' + capitalizedName ](object)

      @prototype['get' + capitalizedSingularizedName + 'ID'] = ()->
        @fetchData() if @isFault
        return @_data[singularizedName + '_id'] or @_data[relationshipDescription.name]?.objectID?.recordId() or null
      @prototype['_get' + capitalizedName] = (callback)->
        return new Promise((resolve,reject)=>
          @fetchData() if @isFault
          async.nextTick(()=>
            if @_data[relationshipDescription.name] is undefined
              @managedObjectContext._getObjectsForRelationship relationshipDescription,@,@managedObjectContext,(err,objects)=>
                if err
                  reject(err)
                else
                  resolve(objects[0] or null)
            else resolve(@_data[relationshipDescription.name]);
          )
        ).asCallback(callback)
      @prototype['_set' + capitalizedName] = (object)->
#        @fetchData() if @isFault
        if object isnt null and object not instanceof ManagedObject
          throw new Error('only ManagedObject instances or null can be set to relationship (given ' + util.format(object) + '; ' + relationshipDescription.entity.name + '=>' + relationshipDescription.name + ')')
        @_setObjectToRelation(object,relationshipDescription,inverseRelationship)
    else
      @prototype['get' + capitalizedName] = @prototype['get' + capitalizedName] or (callback)->
          return @['_get' + capitalizedName](callback)
      @prototype['add' + capitalizedSingularizedName] = @prototype['add' + capitalizedSingularizedName] or (object)->
          return @['_add' + capitalizedSingularizedName](object)
      @prototype['add' + capitalizedName] = @prototype['add' + capitalizedName] or (objects)->
          return @['_add' + capitalizedName](objects)
      @prototype['remove' + capitalizedSingularizedName] = @prototype['remove' + capitalizedSingularizedName] or (object)->
          return @['_remove' + capitalizedSingularizedName](object)
      @prototype['remove' + capitalizedName] = @prototype['remove' + capitalizedName] or (objects)->
          return @['_remove' + capitalizedName](objects)

      @prototype['_get' + capitalizedName] = @prototype['get' + capitalizedSingularizedName + 'Objects'] = (callback)->
        return new Promise((resolve,reject)=>
          @fetchData() if @isFault
          if not Array.isArray(@_data[relationshipDescription.name])
            @managedObjectContext._getObjectsForRelationship relationshipDescription,@,@managedObjectContext,(err,objects)=>
              return reject(err) if err
              if @_relationChanges
                for item in @_relationChanges['added_' + relationshipDescription.name]?
                  ac.addObject(objects,item)
                for item in @_relationChanges['removed_' + relationshipDescription.name]?
                  ac.removeObject(objects,item)
              @_data[relationshipDescription.name] = objects
              resolve(@_data[relationshipDescription.name].slice(0))
          else resolve(@_data[relationshipDescription.name].slice(0));
        ).asCallback(callback)
      @prototype['_add' + capitalizedSingularizedName] = (object)->
        if object not instanceof ManagedObject
          throw new Error('only ManagedObject instances can be added to toMany relationship (given ' + util.format(object) + '; ' + relationshipDescription.entity.name + '=>' + relationshipDescription.name + ')')
        @_addObjectToRelation(object,relationshipDescription,inverseRelationship)
      @prototype['_add' + capitalizedName] = @prototype['add' + capitalizedSingularizedName + 'Objects'] = (objects)->
#        @fetchData() if @isFault
        if not Array.isArray(objects)
          throw new Error('array must be specified in addObjects method (given ' + util.format(objects) + '; ' + relationshipDescription.entity.name + '=>' + relationshipDescription.name + ')')
        for object in objects
          @['add' + capitalizedSingularizedName](object)
      @prototype['_remove' + capitalizedSingularizedName] = (object)->
        if object not instanceof ManagedObject
          throw new Error('only ManagedObject instances can be removed from toMany relationship (given ' + util.format(object) + '; ' + relationshipDescription.entity.name + '=>' + relationshipDescription.name + ')')
        @_removeObjectFromRelation(object,relationshipDescription,inverseRelationship)
      @prototype['_remove' + capitalizedName] = @prototype['remove' + capitalizedSingularizedName + 'Objects'] = (objects)->
        if not Array.isArray(objects)
          throw new Error('array must be specified in removeObjects method (given ' + util.format(objects) + '; ' + relationshipDescription.entity.name + '=>' + relationshipDescription.name + ')')
        for object in objects
          @['remove' + capitalizedSingularizedName](object)
    @

  awakeFromInsert:()->

  awakeFromFetch:()->

  willSave:()->
    for attribute in @entity.getNonTransientAttributes()
      if attribute.info.required and @[attribute.name] is null
        throw new Error('cannot save ' + @entity.name + ', attribute ' + attribute.name + ' is required')

  didSave:()->



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
    if object and object.managedObjectContext isnt @managedObjectContext
      throw new Error('cannot set object to relationship of object in different context')
    if object isnt @_data[relationshipDescription.name]
      prevObject = @_data[relationshipDescription.name];
      singularizedName = _.singularize(relationshipDescription.name)
      @_data[relationshipDescription.name] = object
      delete @_data[singularizedName + '_id']
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
    if object and object.managedObjectContext isnt @managedObjectContext
      throw new Error('cannot add object to relationship of object in different context')
    if not @_data[relationshipDescription.name] or object not in @_data[relationshipDescription.name]
      @_relationChanges = @_relationChanges || {}
      @_relationChanges['added_' + relationshipDescription.name] = @_relationChanges['added_' + relationshipDescription.name] || []
      @_relationChanges['removed_' + relationshipDescription.name] = @_relationChanges['removed_' + relationshipDescription.name] || []

      @_data[relationshipDescription.name] = @_data[relationshipDescription.name] or []
      ac.addObject(@_data[relationshipDescription.name],object)

      if object not in @_relationChanges['removed_' + relationshipDescription.name]
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
    if object and object.managedObjectContext isnt @managedObjectContext
      throw new Error('cannot remove object from relationship of object in different context')
    if not @_data[relationshipDescription.name] or object in @_data[relationshipDescription.name]
      @_relationChanges = @_relationChanges || {}
      @_relationChanges['added_' + relationshipDescription.name] = @_relationChanges['added_' + relationshipDescription.name] || []
      @_relationChanges['removed_' + relationshipDescription.name] = @_relationChanges['removed_' + relationshipDescription.name] || []
      if @_data[relationshipDescription.name]
        ac.removeObject(@_data[relationshipDescription.name],object)

      if object not in @_relationChanges['added_' + relationshipDescription.name]
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
    @managedObjectContext._didUpdateObject(@)
#    @_isUpdated = yes


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
      get: -> !!((@_changes and Object.keys(@_changes).length > 0) or (@_relationChanges and @_relationChanges.length > 0))
    isDeleted:
      get: -> @_isDeleted
    isFault:
      get: -> @_isFault

module.exports = ManagedObject;


