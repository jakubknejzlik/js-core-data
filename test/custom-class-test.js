var assert = require("assert"),
    ManagedObjectModel = require('./../lib/ManagedObjectModel'),
    ManagedObject = require('./../lib/ManagedObject'),
    ManagedObjectContext = require('./../lib/ManagedObjectContext'),
    PersistentStoreCoordinator = require('./../lib/PersistentStoreCoordinator'),
    Car = require('./Classes/Car'),
    Owner = require('./Classes/Owner'),
    User = require('./Classes/User'),
    moment = require('moment');


var store_url = require('./get_storage_url');


describe('custom classes',function(){

    describe('programatically',function(){
        var CoreData = require('../index');

        var db = new CoreData('sqlite://:memory:',{logging:false});

        var BaseUser = db.defineEntity('User',{
            firstname:'string',
            lastname:'string'
        });
        BaseUser.objectClass = User;

        before(function(done){
            db.syncSchema({force:true}).then(done).catch(done);
        });

        it('should support custom methods',function(){
            var context = db.createContext();
            var user = context.create('User',{firstname:'John',lastname:'Doe'});

            assert.ok(user instanceof User);

            assert.equal(user.getFullName(),'John Doe');

            user.setFullName('John2 Doe2');

            assert.equal(user.firstname,'John2');
            assert.equal(user.lastname,'Doe2');
        })
    });

    describe('yaml',function(){
        var objectModel = new ManagedObjectModel(__dirname + '/schemes/car-model-custom-classes.yaml',{'Car':require('./Classes/Car')});
        var storeCoordinator,car,owner;
        before(function(done){
            storeCoordinator = new PersistentStoreCoordinator(objectModel);
            storeCoordinator.addStore(store_url);
            storeCoordinator.persistentStores[0].syncSchema({force:true},function(err){
                if(err)done(err);
                var context = new ManagedObjectContext(storeCoordinator);
                car = context.createObjectWithName('Car');
                owner = context.createObjectWithName('Owner');
                done()
            });
        });
        it('should throw error if no custom file module found',function(){
            assert.throws(function(){
                var model = new ManagedObjectModel(__dirname + '/schemes/car-model-custom-classes-invalid.yaml');
            })
        });
        it('should create object with valid class',function(){
            assert.ok(car instanceof Car);
            assert.ok(owner instanceof Owner)
        });
        it('should be able to call custom methods',function(){
            car.setBrandCustom('test!');
            assert.equal(car.brand,'test!test!')
        });
        it('should call relation methods correctly',function(done){
            car.setOwner(owner);
            car.getOwner(function(err,_owner){
                if(err)return done(err);
                assert.equal(owner,_owner);
                done()
            })
        });
        it('should call custom method with method from parent class',function(done){
            car.setOwner(owner);
            car.getOwnerCustom(function(err,_owner){
                if(err)return done(err);
                assert.equal(owner,_owner);
                done()
            })
        })
    })
});