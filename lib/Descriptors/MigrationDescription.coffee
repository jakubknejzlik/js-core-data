EntityDescription = require('../Descriptors/EntityDescription')

class MigrationDescription
  constructor:(@modelFrom,@modelTo)->
    @entitiesChanges = []
    @attributesChanges = {}
    @relationshipsChanges = {}
#    @indexesChanges = {}
    @scriptsBefore = []
    @scriptsAfter = []



  addEntity:(name)->
    @entitiesChanges.push({entity: @_entityName(name),change:'+'})

  renameEntity:(oldName,newName)->
    @entitiesChanges.push({entity: @_entityName(oldName),change: @_entityName(newName)})

  removeEntity:(name)->
    @entitiesChanges.push({entity: @_entityName(name),change:'-'})


  _entityName:(entity)->
    if entity instanceof EntityDescription
      return entity.name
    return entity

  addAttribute:(entity,name)->
    entityName = @_entityName(entity)
    @attributesChanges[entityName] = @attributesChanges[entityName] or {}
    @attributesChanges[entityName][name] = '+'

  renameAttribute:(entity,name,newName)->
    entityName = @_entityName(entity)
    @attributesChanges[entityName] = @attributesChanges[entityName] or {}
    @attributesChanges[entityName][name] = newName

  removeAttribute:(entity,name)->
    entityName = @_entityName(entity)
    @attributesChanges[entityName] = @attributesChanges[entityName] or {}
    @attributesChanges[entityName][name] = '-'



  addRelationship:(entity,name)->
    entityName = @_entityName(entity)
    @relationshipsChanges[entityName] = @relationshipsChanges[entityName] or {}
    @relationshipsChanges[entityName][name] = '+'

  renameRelationship:(entity,name,newName)->
    entityName = @_entityName(entity)
    @relationshipsChanges[entityName] = @relationshipsChanges[entityName] or {}
    @relationshipsChanges[entityName][name] = newName

  removeRelationship:(entity,name)->
    entityName = @_entityName(entity)
    @relationshipsChanges[entityName] = @relationshipsChanges[entityName] or {}
    @relationshipsChanges[entityName][name] = '-'



#  addIndex:(entityName,name)->
#    @indexesChanges[entityName] = @indexesChanges[entityName] or {}
#    @indexesChanges[entityName][name] = '+'
#
#  renameIndex:(entityName,oldName,newName)->
#    @indexesChanges[entityName] = @indexesChanges[entityName] or {}
#    @indexesChanges[entityName][newName] = oldName
#
#  removeIndex:(entityName,name)->
#    @indexesChanges[entityName] = @indexesChanges[entityName] or {}
#    @indexesChanges[entityName][name] = '-'

  addScriptBefore:(script,name)->
    @scriptsBefore.push({script:script,name:name})

  addScriptAfter:(script,name)->
    @scriptsAfter.push({script:script,name:name})

#  createInverseMigration:()->
#    return null


module.exports = MigrationDescription