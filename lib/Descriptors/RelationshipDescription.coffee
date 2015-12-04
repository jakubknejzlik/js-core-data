PropertyDescription = require('./PropertyDescription')

class RelationshipDescription extends PropertyDescription
  @deleteRules:{
    NO_ACTION:'no_action',
    NULLIFY:'nullify',
    CASCADE:'cascade',
    DENY:'deny'
  }

  constructor:(name,@destinationEntity,@toMany,@inverseRelationshipName,entity,@deleteRule = RelationshipDescription.deleteRules.NULLIFY)->
    if not @destinationEntity
      throw new Error('destination entity cannot be null for relationship \'' + name + '\'')
#    @deleteRule = @deleteRule or RelationshipDescription.deleteRules.NULLIFY
    super(name,entity)

  inverseRelationship:->
    if not @inverseRelationshipName
      throw new Error('inverse relationship for '+@entity.name+'->'+@name + ' not defined')
    inv = @destinationEntity.relationshipsByName()[@inverseRelationshipName];
    if not inv
      throw new Error('could not found inverse relationship \''+@inverseRelationshipName+'\' for relationship '+@entity.name+'->'+@name)
    inv

  toString: ->
    @entity.name + '=>' + @name

  getOnDeleteRule:()->
    switch @deleteRule
      when RelationshipDescription.deleteRules.NO_ACTION
        return 'NO ACTION'
      when RelationshipDescription.deleteRules.CASCADE
        return 'CASCADE'
      when RelationshipDescription.deleteRules.DENY
        return 'RESTRICT'
      else
        return 'SET NULL'


module.exports = RelationshipDescription;