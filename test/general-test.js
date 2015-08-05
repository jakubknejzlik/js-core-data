var assert = require("assert"),
    ManagedObjectModel = require('./../lib/ManagedObjectModel'),
    ManagedObject = require('./../lib/ManagedObject'),
    ManagedObjectID = require('./../lib/ManagedObjectID'),
    ManagedObjectContext = require('./../lib/ManagedObjectContext'),
    PersistentStoreCoordinator = require('./../lib/PersistentStoreCoordinator');

describe('general tests',function(){
    var objectModel = new ManagedObjectModel(__dirname + '/schemes/deep-relation-model.yaml');

    describe('ObjectID',function(){
        it('shouldn\'t throw creating ManagedObjectID with string and number',function(){
            assert.doesNotThrow(function(){
                var objID = new ManagedObjectID('1');
                assert.equal(objID.recordId(),'1');
            })
            assert.doesNotThrow(function(){
                var objID = new ManagedObjectID(1);
                assert.equal(objID.recordId(),'1');
            })
        })
    })
})