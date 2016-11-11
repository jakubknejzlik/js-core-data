var assert = require("assert"),
    ManagedObjectModel = require('./../lib/ManagedObjectModel'),
    ManagedObjectContext = require('./../lib/ManagedObjectContext'),
    PersistentStoreCoordinator = require('./../lib/PersistentStoreCoordinator'),
    ModelYamlParser = require('../lib/Parsers/ModelYamlParser'),
    moment = require('moment'),
    fs = require('fs');

var store_url = require('./get_storage_url');

describe('serialization',function(){
    var objectModel = new ManagedObjectModel();
    ModelYamlParser.fillModelFromYaml(objectModel,fs.readFileSync(__dirname + '/schemes/object-test-model.yaml'),{Hello: require('./Classes/Hello')})
    describe('json',function(){
        var storeCoordinator,timestamp = Math.round(Date.now() / 1000);
        var date = new Date(timestamp*1000);
        function deleteAll(storeCoordinator,done){
            var context = new ManagedObjectContext(storeCoordinator)
            context.getObjects('Hello',function(err,objects){
                if(err)return done(err);
                objects.forEach(function(obj){
                    context.deleteObject(obj);
                })
                context.save(done);
            })
        }
        before(function(done){
            storeCoordinator = new PersistentStoreCoordinator(objectModel);
            storeCoordinator.addStore(store_url)
            storeCoordinator.persistentStores[0].syncSchema({force:true}).then(function(){
                deleteAll(storeCoordinator,done);
            }).catch(done)
        })
        it('should create generate valid JSON',function(){
            var context = new ManagedObjectContext(storeCoordinator)
            var obj = context.create('Hello')
            obj.bool = true;
            obj.name = 'test';
            obj.int = 1004;
            obj.decim = 0.55;
            obj.float = 10.505;
            obj.double = 100.5054;
            obj.email = 'jackie@gmail.com';
            obj.url = 'http://www.google.com';
            obj.date = date;
            obj.timestamp = date;
            obj.transformable = {aa:'bb'};
            obj.transformableArray = [{aa:'bb'}];
            obj.firstname = 'Johna'
            var json = '{"id":'+obj.objectID.recordId()+',"awakeFromInsertValue":"awaken","awakeFromFetchValue":null,"saveValue":null,"uuid":"'+obj.uuid+'","name":"test","int":1004,"bigint":null,"bool":true,"decim":0.55,"float":10.505,"double":100.5054,"email":"jackie@gmail.com","url":"http://www.google.com","enum":null,"date":'+JSON.stringify(date)+',"timestamp":'+JSON.stringify(date)+',"data":null,"shortString":null,"transformable":{"aa":"bb"},"transformableArray":[{"aa":"bb"}],"firstname":"Johna","lastname":"Doe","fullName":"Johna Doe","fullName2":"Johna Doe","world_id":null}';
            assert.equal(JSON.stringify(obj.toJSON()),json)
        })

        it('should create generate valid JSON for empty object',function(){
            var context = new ManagedObjectContext(storeCoordinator)
            var obj = context.createObjectWithName('Hello');
            obj.date = null;
            obj.timestamp = null;
            var json = '{"id":'+obj.objectID.recordId()+',"awakeFromInsertValue":"awaken","awakeFromFetchValue":null,"saveValue":null,"uuid":"'+obj.uuid+'","name":"defVal","int":null,"bigint":null,"bool":null,"decim":null,"float":null,"double":null,"email":null,"url":null,"enum":null,"date":null,"timestamp":null,"data":null,"shortString":null,"transformable":null,"transformableArray":null,"firstname":"John","lastname":"Doe","fullName":"John Doe","fullName2":"John Doe","world_id":null}';
            assert.equal(JSON.stringify(obj.toJSON()),json);
        })
    })
})