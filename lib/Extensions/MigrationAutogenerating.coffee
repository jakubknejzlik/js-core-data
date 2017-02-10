ManagedObjectModel = require('../ManagedObjectModel')
MigrationDescription = require('../Descriptors/MigrationDescription')

diff = (arr, arr2) =>
  return arr.filter((x) =>
    return x not in arr2
  )

ManagedObjectModel::autogenerateMigrationFromModel = (modelFrom, options)->

  migration = new MigrationDescription(modelFrom,@)

  oldEntities = Object.keys(modelFrom.entities)
  newEntities = Object.keys(@entities)
  addedEntities = diff(newEntities, oldEntities)
  removedEntities = diff(oldEntities, newEntities)
  sameEntities = diff(newEntities, addedEntities)

  for entity in addedEntities
    migration.addEntity(entity)
  for entity in removedEntities
    migration.removeEntity(entity)

  for entityName in sameEntities
    newEntity = @getEntity(entityName)
    oldEntity = modelFrom.getEntity(entityName)

    newAttributes = Object.keys(newEntity.attributesByName())
    oldAttributes = Object.keys(oldEntity.attributesByName())
    addedAttributes = diff(newAttributes, oldAttributes)
    removedAttributes = diff(oldAttributes, newAttributes)

    for attribute in addedAttributes
      migration.addAttribute(entityName,attribute)
    for attribute in removedAttributes
      migration.removeAttribute(entityName,attribute)

    newRelationships = Object.keys(newEntity.relationshipsByName())
    oldRelationships = Object.keys(oldEntity.relationshipsByName())
    addedRelationships = diff(newRelationships, oldRelationships)
    removedRelationships = diff(oldRelationships, newRelationships)

    for relationship in addedRelationships
      migration.addRelationship(entityName,relationship)
    for relationship in removedRelationships
      migration.removeRelationship(entityName,relationship)


  return migration