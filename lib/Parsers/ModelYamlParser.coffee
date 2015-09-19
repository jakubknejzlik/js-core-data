yaml = require('js-yaml')
fs = require('fs')
EntityDescription = require('./../Descriptors/EntityDescription')
AttributeDescription = require('./../Descriptors/AttributeDescription')
RelationshipDescription = require('./../Descriptors/RelationshipDescription')
ManagedObjectModel = require('./../ManagedObjectModel')

class ModelYamlParser extends Object
  @objectModelFromYamlFile: (file)->
    objectModel = new ManagedObjectModel();
    @fillModelFromYamlFile(objectModel,file)
    return objectModel
  @objectModelFromYaml: (yamlSource)->
    objectModel = new ManagedObjectModel();
    @fillModelFromYaml(objectModel,yamlSource)
    return objectModel
  @fillModelFromYamlFile:(objectModel,file)->
    @fillModelFromYaml(objectModel,fs.readFileSync(file,'utf8'))
  @fillModelFromYaml:(objectModel,yamlSource)->
    try
      entities = {}
      entitiesArray = []
      _entities = yaml.safeLoad(yamlSource)
      for entityName,info of _entities
        entity = new EntityDescription(entityName,info)
        entities[entityName] = entity
        entitiesArray.push(entity)

      for entityName,info of _entities
        for relationshipName,relationshipInfo of (info.relationships or info.relations)
          relationship = new RelationshipDescription(relationshipName,entities[relationshipInfo.entity],relationshipInfo.toMany,relationshipInfo.inverse);
          if relationshipInfo.delete_rule or relationshipInfo.deleteRule
            relationship.deleteRule = relationshipInfo.delete_rule or relationshipInfo.deleteRule
          entities[entityName].addRelationship(relationship)


      for entity in entitiesArray
        objectModel.addEntity(entity)
    catch e
      throw new Error('Could not parse yaml, reason: ' + e.message)







module.exports = ModelYamlParser;