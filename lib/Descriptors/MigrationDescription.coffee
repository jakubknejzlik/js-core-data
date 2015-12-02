class MigrationDescription
  constructor:(@modelFrom,@modelTo)->
    @entitiesChanges = []
    @attributesChanges = {}
    @relationshipsChanges = {}
#    @indexesChanges = {}
    @scriptsBefore = []
    @scriptsAfter = []



  addEntity:(name)->
    @entitiesChanges.push({entity:name,change:'+'})

  renameEntity:(oldName,newName)->
    @entitiesChanges.push({entity:oldName,change:newName})

  removeEntity:(name)->
    @entitiesChanges.push({entity:name,change:'-'})


  addAttribute:(entityName,name)->
    @attributesChanges[entityName] = @attributesChanges[entityName] or {}
    @attributesChanges[entityName][name] = '+'

  renameAttribute:(entityName,name,newName)->
    @attributesChanges[entityName] = @attributesChanges[entityName] or {}
    @attributesChanges[entityName][name] = newName

  removeAttribute:(entityName,name)->
    @attributesChanges[entityName] = @attributesChanges[entityName] or {}
    @attributesChanges[entityName][name] = '-'



  addRelationship:(entityName,name)->
    @relationshipsChanges[entityName] = @relationshipsChanges[entityName] or {}
    @relationshipsChanges[entityName][name] = '+'

  renameRelationship:(entityName,name,newName)->
    @relationshipsChanges[entityName] = @relationshipsChanges[entityName] or {}
    @relationshipsChanges[entityName][name] = newName

  removeRelationship:(entityName,name)->
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