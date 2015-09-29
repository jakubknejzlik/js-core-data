class MigrationDescription
  construct:(@modelFrom,@modelTo)->



  appendMigration:(migration)->




  addEntity:(name)->

  renameEntity:(oldName,newName)->

  removeEntity:(name)->


  addColumn:(entityName,name)->

  renameColumn:(entityName,oldName,newName)->

  removeColumn:(entityName,name)->



  addRelationship:(entityName,name)->

  renameRelationship:(entityName,oldName,newName)->

  removeRelationship:(entityName,name)->



  addIndex:(entityName,name)->

  renameIndex:(entityName,oldName,newName)->

  removeIndex:(entityName,name)->


module.exports = MigrationDescription