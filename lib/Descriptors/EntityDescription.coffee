AttributeDescription = require('./AttributeDescription')
RelationshipDescription = require('./RelationshipDescription')
ManagedObject = require('./../ManagedObject')
path = require('path')

class EntityDescription
  constructor:(@name, initData) ->
    @attributes = []
    @relationships = []
    @indexes = []

    @_attributesByName = {}
    @_relationshipsByName = {}

    if initData
      if typeof initData.class is 'string'
        @objectClassName = initData.class
      else if typeof initData.class is 'function'
        @objectClass = initData.class
      for attributeKey,attributeInfo of initData.columns
        if attributeInfo not instanceof Object
          attributeInfo = {type:attributeInfo}
        attr = new AttributeDescription(attributeInfo.type,attributeInfo,attributeKey,null);
        if attributeInfo.options
          attr.options = attributeInfo.options
        @addAttribute(attr)
      if initData.indexes
        for index in initData.indexes
          if typeof index is 'string'
            index = {name:index,columns:[index]}
          @addIndex(index.name,index.type,index.columns)

  addAttribute : (attribute) ->
    if attribute instanceof AttributeDescription
      attribute.entity = this
      @attributes.push(attribute)
      @_attributesByName[attribute.name] = attribute;
    else
      throw new Error 'attribute ' + attribute + ' is not AttributeDescription'
    this

  addRelationship : (relationship) ->
    if relationship instanceof RelationshipDescription
      relationship.entity = this
      @relationships.push(relationship)
      @_relationshipsByName[relationship.name] = relationship
    else
      throw new Error 'relationship ' + relationship + ' is not AttributeDescription'
    this

  addIndex:(name,type = 'key',columns)->
    if not name
      name = columns.join('_')
    @indexes.push({name:name,type:type,columns:columns})

  getAttribute: (name)->
    attribute = @_attributesByName[name]
    if not attribute
      throw new Error('attribute ' + @name + '=>' + name + ' not found')
    return attribute

  attributesByName : ->
    @_attributesByName

  getRelationship: (name)->
    relationship = @_relationshipsByName[name]
    if not relationship
      throw new Error('relationship ' + @name + '=>' + name + ' not found')
    return relationship

  relationshipsByName : ->
    @_relationshipsByName

  relationshipByName : (name)->
    @_relationshipsByName[name]

module.exports = EntityDescription;