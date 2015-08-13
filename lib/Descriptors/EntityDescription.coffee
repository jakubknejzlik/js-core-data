AttributeDescription = require('./AttributeDescription')
RelationshipDescription = require('./RelationshipDescription')
ManagedObject = require('./../ManagedObject')
path = require('path')

class EntityDescription
  constructor:(@name) ->
    @attributes = []
    @relationships = []

    @_attributesByName = {}
    @_relationshipsByName = {}

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

  attributesByName : ->
    @_attributesByName

  relationshipsByName : ->
    @_relationshipsByName

  relationshipByName : (name)->
    @_relationshipsByName[name]

module.exports = EntityDescription;