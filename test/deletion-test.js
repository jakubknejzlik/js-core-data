var assert = require("assert"),
    ManagedObjectModel = require('./../lib/ManagedObjectModel'),
    ManagedObjectContext = require('./../lib/ManagedObjectContext'),
    PersistentStoreCoordinator = require('./../lib/PersistentStoreCoordinator'),
    ModelYamlParser = require('../lib/Parsers/ModelYamlParser'),
    fs = require('fs'),
    moment = require('moment');

var store_url = require('./get_storage_url');

describe('delete rules',function(){
    var objectModel = new ManagedObjectModel();
    ModelYamlParser.fillModelFromYaml(objectModel,fs.readFileSync(__dirname + '/schemes/deletion-test.yaml'))
    var storeCoordinator,department;

    before(function(){
        storeCoordinator = new PersistentStoreCoordinator(objectModel);
        storeCoordinator.addStore(store_url)
        return storeCoordinator.persistentStores[0].syncSchema({force:true});
    })
//    after(function(done){
//        var context = new ManagedObjectContext(storeCoordinator)
//        context.getObjects('Person',null,null,function(err,objects){
//            if(err)return done(err)
//            objects.forEach(function(obj){
//                context.deleteObject(obj)
//            })
//            context.getObjects('Department',null,null,function(err,objects){
//                if(err)return done(err)
//                objects.forEach(function(obj){
//                    context.deleteObject(obj)
//                })
//                context.save(done)
//            })
//        })
//    })

    it('should create data successfuly',function(done){
        var context = new ManagedObjectContext(storeCoordinator)
        var company = context.createObjectWithName("Company");
        company.name = 'test company';
        department = context.createObjectWithName("Department")
        department.name = 'test department';

        var person = context.createObjectWithName("Person")
        person.name = 'Jackie';
//        department.addPerson(person);
        person.setDepartment(department)

        company.addDepartment(department)

        context.save(done)
    })

    //it('should deny deletion',function(done){
    //    var context = new ManagedObjectContext(storeCoordinator)
    //    context.getObjectWithObjectID(department.objectID,function(err,object){
    //        if(err)return done(err)
    //        context.deleteObject(object)
    //        context.save(function(err){
    //            assert.throws(function(){
    //                if(err)throw err;
    //            })
    //            done()
    //        })
    //    })
    //})
    it('should not deny deletion on empty relation',function(done){
        var context = new ManagedObjectContext(storeCoordinator)
        var department = context.createObjectWithName('Department');
        context.deleteObject(department)
        context.save(done)
    })
    it('should delete object from persistent relation(nullify)',function(done){
        var context = new ManagedObjectContext(storeCoordinator)
        var context2 = new ManagedObjectContext(storeCoordinator)
        var person1 = context.createObjectWithName('Person');
        var person2 = context.createObjectWithName('Person');
        var department = context.createObjectWithName('Department');
        department.addPersons([person1,person2])
        context.save(function(err){
            assert.ifError(err)
            context2.getObjectWithObjectID(department.objectID,function(err,_department){
                assert.ifError(err);
                context2.getObjectWithObjectID(person1.objectID,function(err,_person1){
                    assert.ifError(err)
                    _department.removePerson(_person1)
                    context2.save(function(err){
                        assert.ifError(err)
//                            context.reset()
                        department.getPersons(function(err,objects){
                            assert.ifError(err)
                            assert.equal(objects.indexOf(_person1),-1)
                            done()
                        })
                    })
                })
            })
        })
    })
    it('should nullify object',function(done){
        var context = new ManagedObjectContext(storeCoordinator)
        var context2 = new ManagedObjectContext(storeCoordinator)
        var person = context.createObjectWithName('Person');
        var stuff = context.createObjectWithName('Stuff');
        stuff.setOwner(person)
        context.save(function(err){
            assert.ifError(err);
            context.deleteObject(person)
            context.save(function(err){
                assert.ifError(err);
                context2.getObjectWithObjectID(stuff.objectID,function(err,_stuff){
                    assert.ifError(err)
                    _stuff.getOwner(function(err,_owner){
                        assert.strictEqual(_owner,null)
                        done()
                    })
                })
            })
        })
    })
    it('should nullify object on toMany',function(done){
        var context = new ManagedObjectContext(storeCoordinator)
        var context2 = new ManagedObjectContext(storeCoordinator)
        var person1 = context.createObjectWithName('Person');
        var person2 = context.createObjectWithName('Person');
        var person3 = context.createObjectWithName('Person');

        person1.name = 'collegue1';
        person2.name = 'collegue2';
        person3.name = 'collegue3';

        person1.addCollegue(person2)
        person1.addCollegue(person3)

        person2.addCollegue(person3)

        person3.getCollegues(function(err,_persons){
            assert.notEqual(_persons.indexOf(person1),-1)
            assert.notEqual(_persons.indexOf(person2),-1)
            context.save(function(err){
                assert.ifError(err)
                context.deleteObject(person1)
                context.save(function(err){
                    assert.ifError(err)
                    context2.getObjectWithObjectID(person3.objectID,function(err,_person){
                        assert.ifError(err)
                        context2.getObjectWithObjectID(person2.objectID,function(err,_person2){
                            assert.ifError(err)
                            context2.getObjectWithObjectID(person1.objectID,function(err,_person1){
                                assert.ifError(err)
                                _person.getCollegues(function(err,_persons){
                                    assert.equal(_persons.indexOf(_person1),-1)
                                    assert.notEqual(_persons.indexOf(_person2),-1,person2.objectID.toString())
                                    done()
                                })
                            })
                        })
                    })
                })
            })
        })
    })
//    it('should cascade object deletion',function(done){
//        var context = new ManagedObjectContext(storeCoordinator)
//        var context2 = new ManagedObjectContext(storeCoordinator)
//        var company = context.createObjectWithName('Company')
//        var department1 = context.createObjectWithName('Department')
//        var department2 = context.createObjectWithName('Department')
//
//        company.addDepartments([department1]);
//        department2.setParent(department1)
//
//        context.save(function(err){
//            assert.ifError(err)
//            context.deleteObject(company)
//            context.save(function(err){
//                assert.ifError(err)
//                context2.getObjectWithObjectID(department1.objectID,function(err,_department1){
//                    assert.ifError(err)
//                    context2.getObjectWithObjectID(department2.objectID,function(err,_department2){
//                        assert.ifError(err)
//                        assert.strictEqual(_department1,null)
//                        assert.strictEqual(_department2,null)
//                        done()
//                    })
//                })
//            })
//        })
////        done()
//
//    })
//    it('should remove object many-2-many on removal and delete',function(done){
//        var context = new ManagedObjectContext(storeCoordinator)
//        var context2 = new ManagedObjectContext(storeCoordinator)
//        var deliveryBoy = context.createObjectWithName('DeliveryBoy')
//        deliveryBoy.name = 'hey boy';
//        var department1 = context.createObjectWithName('Department')
//        department1.name = 'dep1';
//        var department2 = context.createObjectWithName('Department')
//        department2.name = 'dep2';
//
//        deliveryBoy.addDepartments([department2]);
//
//        context.save(function(err){
////            assert.ifError(err);
////            deliveryBoy.removeDepartment(department1);
//            context.deleteObject(department2);
//            context.save(function(err){
//                assert.ifError(err);
//                deliveryBoy.getDepartments(function(err,departments){
//                    assert.ifError(err);
//                    assert.equal(departments.length,0);
//                    context2.getObjectWithObjectID(deliveryBoy.objectID,function(err,delboy){
//                        assert.ifError(err);
//                        delboy.getDepartments(function(err,departments){
//                            assert.ifError(err);
//                            assert.equal(departments.length,0);
//                            done()
//                        })
//                    })
//                })
//            })
//        })
//    })
})