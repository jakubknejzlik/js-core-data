yaml = require('js-yaml')
fs = require('fs')
EntityDescription = require('./../Descriptors/EntityDescription')
AttributeDescription = require('./../Descriptors/AttributeDescription')
RelationshipDescription = require('./../Descriptors/RelationshipDescription')
ManagedObjectModel = require('./../ManagedObjectModel')

class ModelYamlParser extends Object
  @objectModelFromYaml: (yamlSource, objectClasses)->
    objectModel = new ManagedObjectModel();
    @fillModelFromYaml(objectModel, yamlSource, objectClasses)
    return objectModel

  @fillModelFromYaml:(objectModel, yamlSource, objectClasses = {})->
    try
      entities = {}
      entitiesArray = []
      _entities = yaml.safeLoad(yamlSource)

      for entityName,info of _entities
        entityClass = objectClasses[entityName or info.class]
        if info.class and not entityClass
          throw new Error('Could not find objectClass ' + info.class)
        entity = objectModel.defineEntity(entityName,info.columns,{
          class: entityClass
        })
        entities[entityName] = entity
        entitiesArray.push(entity)

      for entityName,info of _entities
        for relationshipName,relationshipInfo of (info.relationships or info.relations)
          relationship = new RelationshipDescription(relationshipName,entities[relationshipInfo.entity],relationshipInfo.toMany,relationshipInfo.inverse);
          if relationshipInfo.delete_rule or relationshipInfo.deleteRule
            relationship.deleteRule = relationshipInfo.delete_rule or relationshipInfo.deleteRule
          entities[entityName].addRelationship(relationship)
    catch e
      throw new Error('Could not parse yaml, reason: ' + e.message)

module.exports = ModelYamlParser;