var assert = require("assert"),
    ManagedObjectModel = require('./../lib/ManagedObjectModel'),
    ManagedObject = require('./../lib/ManagedObject'),
    ManagedObjectContext = require('./../lib/ManagedObjectContext'),
    PersistentStoreCoordinator = require('./../lib/PersistentStoreCoordinator');

var mysql_store_url = 'mysql://root@localhost/test';

describe('deep relation',function(){
    var objectModel = new ManagedObjectModel(__dirname + '/schemes/deep-relation-model.yaml');

    describe('parent class',function(){
        var storeCoordinator;
        before(function(done){
            storeCoordinator = new PersistentStoreCoordinator(objectModel);
            storeCoordinator.addStore(PersistentStoreCoordinator.STORE_TYPE_MYSQL,mysql_store_url)
            storeCoordinator.persistentStores[0].syncSchema({force:true},function(err){
                if(err)done(err)
                done()
            });
        })
        it('should load prepare data',function(done){
            var context = new ManagedObjectContext(storeCoordinator)
            var ent1 = context.createObjectWithName('Entity1')
            ent1.name = 'entity1';
            var ent2 = context.createObjectWithName('Entity2')
            ent2.name = 'entity2';
            var ent3 = context.createObjectWithName('Entity3')
            ent3.name = 'entity3';
            var ent4 = context.createObjectWithName('Entity4')
            ent4.name = 'entity4';

            ent4.setParent(ent3);
            ent3.setParent(ent2);
            ent2.setParent(ent1);

            context.save(done);
        })
        it('should load all toOne relationships',function(done){
            var newStoreCoordinator = new PersistentStoreCoordinator(objectModel);
            newStoreCoordinator.addStore(PersistentStoreCoordinator.STORE_TYPE_MYSQL,mysql_store_url)
            storeCoordinator.persistentStores[0].syncSchema({force:false},function(err){
                assert.ifError(err)
                var context = new ManagedObjectContext(newStoreCoordinator)
                context.getObjects('Entity4',function(err,objects){
                    var entity4 = objects[0];
                    assert.ifError(err)
                    assert.equal(entity4.name,'entity4');
                    entity4.getParent(function(err,entity3){
                        assert.ifError(err)
                        assert.equal(entity3.name,'entity3');
                        entity3.getParent(function(err,entity2){
                            assert.ifError(err);
                            assert.equal(entity2.name,'entity2');
                            entity2.getParent(function(err,entity1){
                                assert.ifError(err);
                                assert.equal(entity1.name,'entity1');
                                done();
                            })
                        })
                    })
                })
            });
        })
    })
})