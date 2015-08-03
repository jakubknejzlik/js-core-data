PropertyDescription = require('./PropertyDescription')

class RelationshipDescription extends PropertyDescription
  @deleteRules:{
    NO_ACTION:'no_action',
    NULLIFY:'nullify',
    CASCADE:'cascade',
    DENY:'deny'
  }

  constructor:(name,@destinationEntity,@toMany,@inverseRelationshipName,entity)->
    if not @destinationEntity
      throw new Error('destination entity cannot be null for relationship \'' + name + '\'')
    @deleteRule = RelationshipDescription.deleteRules.NULLIFY
    super(name,entity)

  inverseRelationship:->
    inv = @destinationEntity.relationshipsByName()[@inverseRelationshipName];
    if not inv
      throw new Error('could not found inverse relationship \''+@inverseRelationshipName+'\' for relationship '+@entity.name+'->'+@name)
    inv

  toString: ->
    @name + '(' + @entity + ')'

module.exports = RelationshipDescription;