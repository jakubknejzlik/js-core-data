var assert = require("assert"),
    ManagedObjectModel = require('./../lib/ManagedObjectModel'),
    ManagedObject = require('./../lib/ManagedObject'),
    ManagedObjectContext = require('./../lib/ManagedObjectContext'),
    PersistentStoreCoordinator = require('./../lib/PersistentStoreCoordinator'),
    Car = require('./Classes/Car'),
    Owner = require('./Classes/Owner'),
    moment = require('moment');

var mysql_store_url = 'mysql://root@localhost/test';

describe('custom classes',function(){
    var objectModel = new ManagedObjectModel(__dirname + '/schemes/car-model-custom-classes.yaml',{'Car':require('./Classes/Car')});


    describe('parent class',function(){
        var storeCoordinator,car,owner;
        before(function(done){
            storeCoordinator = new PersistentStoreCoordinator(objectModel);
            storeCoordinator.addStore(PersistentStoreCoordinator.STORE_TYPE_MYSQL,mysql_store_url)
            storeCoordinator.persistentStores[0].syncSchema({force:true},function(err){
                if(err)done(err)
                var context = new ManagedObjectContext(storeCoordinator)
                car = context.createObjectWithName('Car')
                owner = context.createObjectWithName('Owner')
                done()
            });
        })
        it('should throw error if no custom file module found',function(){
            assert.throws(function(){
                var model = new ManagedObjectModel(__dirname + '/schemes/car-model-custom-classes-invalid.yaml');
            })
        })
        it('should create object with valid class',function(){
            assert.ok(car instanceof Car)
            assert.ok(owner instanceof Owner)
        })
        it('should be able to call custom methods',function(){
            car.setBrandCustom('test!');
            assert.equal(car.brand,'test!test!')
        })
        it('should call relation methods correctly',function(done){
            car.setOwner(owner)
            car.getOwner(function(err,_owner){
                if(err)return done(err);
                assert.equal(owner,_owner)
                done()
            })
        })
        it('should call custom method with method from parent class',function(done){
            car.setOwner(owner)
            car.getOwnerCustom(function(err,_owner){
                if(err)return done(err);
                assert.equal(owner,_owner)
                done()
            })
        })
    })
})