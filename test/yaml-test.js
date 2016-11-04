var assert = require("assert"),
    ManagedObjectModel = require('./../lib/ManagedObjectModel'),
    ModelYamlParser = require('../lib/Parsers/ModelYamlParser')
    fs = require('fs');

describe('yaml',function(){
    var objectModel;
    before(function(){
        objectModel = new ManagedObjectModel();
        ModelYamlParser.fillModelFromYaml(objectModel,fs.readFileSync(__dirname + '/schemes/test-model.yaml','utf-8'))
    })

    it('should fail loading invalid scheme',function(){
        assert.throws(function(){
            objectModel = new ManagedObjectModel();
            ModelYamlParser.fillModelFromYaml(objectModel,fs.readFileSync(__dirname + '/schemes/relationship-invalid-test.yaml','utf-8'))
        })
    })

    it('should load from yaml source',function(){
        assert.doesNotThrow(function(){
            objectModel = new ManagedObjectModel();
            ModelYamlParser.fillModelFromYaml(objectModel,fs.readFileSync(__dirname + '/schemes/test-model.yaml'))
        })
    })

    it('number entities',function(){
        assert.equal(Object.keys(objectModel.entities).length,2)
    })
    it('car entity',function(){
        assert.ok(objectModel.entities.Car)
    })
    it('car entity attributes',function(){
        var attributes = objectModel.entities.Car.attributes;
        assert.ok(attributes)
        assert.equal(attributes[0].name,'name')
        assert.equal(attributes[1].name,'brand')
    })

    it('should parse relationships',function(){
        var relationships = objectModel.entities.Car.relationshipsByName()
        assert.ok(relationships.owner)
    })
})