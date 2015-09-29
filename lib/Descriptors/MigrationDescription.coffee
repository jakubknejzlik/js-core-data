class MigrationDescription
  construct:(@modelFrom,@modelTo)->



  appendMigration:(migration)->




  addEntity:(name)->

  renameEntity:(oldName,newName)->

  removeEntity:(name)->


  addAttribute:(entityName,name)->

  renameAttribute:(entityName,oldName,newName)->

  removeAttribute:(entityName,name)->



  addRelationship:(entityName,name)->

  renameRelationship:(entityName,oldName,newName)->

  removeRelationship:(entityName,name)->



  addIndex:(entityName,name)->

  renameIndex:(entityName,oldName,newName)->

  removeIndex:(entityName,name)->


module.exports = MigrationDescription