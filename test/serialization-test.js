var assert = require("assert"),
    ManagedObjectModel = require('./../lib/ManagedObjectModel'),
    ManagedObjectContext = require('./../lib/ManagedObjectContext'),
    PersistentStoreCoordinator = require('./../lib/PersistentStoreCoordinator'),
    moment = require('moment');

//var store_url = 'mysql://root@localhost/test';
var store_url = 'sqlite://:memory:';

describe('serialization',function(){
    var objectModel = new ManagedObjectModel(__dirname + '/schemes/attribute-test-model.yaml');
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
            storeCoordinator.persistentStores[0].syncSchema({force:true},function(err){
                if(err)return done(err);
                deleteAll(storeCoordinator,done);
            });
        })
        it('should create generate valid JSON',function(){
            var context = new ManagedObjectContext(storeCoordinator)
            var obj = context.createObjectWithName('Hello')
            obj.bool = true;
            obj.name = 'test';
            obj.int = 1600;
            obj.decim = 0.55;
            obj.float = 10.505;
            obj.double = 100.5054;
            obj.email = 'jackie@gmail.com';
            obj.url = 'http://www.google.com';
            obj.date = date;
            obj.timestamp = timestamp;
            var json = '{"id":'+obj.objectID.recordId()+',"name":"test","int":1600,"bool":true,"decim":0.55,"float":10.505,"double":100.5054,"email":"jackie@gmail.com","url":"http://www.google.com","date":'+JSON.stringify(date)+',"timestamp":'+timestamp+',"data":null,"shortString":null}';
            assert.equal(JSON.stringify(obj.toJSON()),json)
        })

        it('should create generate valid JSON for empty object',function(){
            var context = new ManagedObjectContext(storeCoordinator)
            var obj = context.createObjectWithName('Hello')
            var json = '{"id":'+obj.objectID.recordId()+',"name":null,"int":null,"bool":null,"decim":null,"float":null,"double":null,"email":null,"url":null,"date":null,"timestamp":null,"data":null,"shortString":null}';
            assert.equal(JSON.stringify(obj.toJSON()),json)
        })
    })
})