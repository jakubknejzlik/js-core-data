var assert = require("assert"),
    PersistentStoreCoordinator = require('./../lib/PersistentStoreCoordinator'),
    AttributeDescription = require('./../lib/Descriptors/AttributeDescription'),
    RelationshipDescription = require('./../lib/Descriptors/RelationshipDescription'),
    EntityDescription = require('./../lib/Descriptors/EntityDescription'),
    ManagedObjectModel = require('./../lib/ManagedObjectModel'),
    ManagedObjectContext = require('./../lib/ManagedObjectContext'),
    ModelYamlParser = require('./../lib/Parsers/ModelYamlParser'),
    Predicate = require('./../lib/FetchClasses/Predicate'),
    SortDescriptor= require('./../lib/FetchClasses/SortDescriptor'),
    CoreData = require('../index');
var async = require('async');
var fs = require('fs');

var store_url = require('./get_storage_url');

var coreData = new CoreData(store_url,{
    logging:false
});

coreData.createModelFromYaml(fs.readFileSync(__dirname + '/schemes/car-model.yaml'),{Car: require('./Classes/Car')})

describe('Context', function(){
    describe('store stuff',function(){

        it('should throw error when creating coordinator with null object model',function(){
            assert.throws(function(){
                new PersistentStoreCoordinator();
            },'Cannot create coordinator without object model')
        })
    });

    describe('context',function(){

        before(function(done){
            coreData.syncSchema({force:true}).then(done).catch(done);
        });

        describe('object creation', function(){
            var context;
            var object;

            before(function(){
                context = coreData.createContext();
                object = context.createObjectWithName('Car');
            });
            after(function(done){
                context.getObjectWithObjectID(object.objectID,function(err,object){
                    context.deleteObject(object);
                    context.save(done)
                })
            });

            it('should insert object into context.insertedObject after creating', function(){
                assert.notEqual(-1, context.insertedObjects.indexOf(object));
            });
            it('should set flag isInserted of object to true',function(){
                assert.equal(true,object.isInserted);
            });
            it('should set flag hasChanges of object to true',function(){
                assert.equal(true,object.hasChanges);
            });
            it('should set flag hasChanges of context to true',function(){
                assert.equal(true,context.hasChanges);
            });
            it('shouldn\'t be fault',function(){
                assert.equal(object.isFault,false);
            });
            it('shouldn\'t fail saving', function(done){
                context.save(done);
            });
            it('should set flag isInserted of object to false after save',function(){
                assert.equal(false,object.isInserted);
            });
            it('should set flag hasChanges of object to false after save',function(){
                assert.equal(false,object.hasChanges);
            });
            it('should set flag hasChanges of context to false after save',function(){
                assert.equal(false,context.hasChanges);
            });
            it('objectID shouldn\'t be temporary after save',function(){
                assert.equal(object.objectID.isTemporaryID,false);
            });

            it('shouldn\'t assign persistent ObjectID on error save',function(done){
                var tempContext = coreData.createContext();
                var car1 = tempContext.create('Car',{uid:'uid'});
                var car2 = tempContext.create('Car',{uid:'uid'});
                tempContext.save().then(function(){
                    done(new Error('should not save successfuly'))
                }).catch(function(err){
                    assert.ok(err);
                    assert.equal(car1.objectID.isTemporaryID,true);
                    assert.equal(car2.objectID.isTemporaryID,true);
                    done()
                })
            });

            it('should set toOne relation',function(done){
                var tempContext = coreData.createContext();
                var car = context.createObjectWithName('Car');
                var owner = context.createObjectWithName('Owner');
                car.setOwner(owner);
                var values = car.getValues();
                assert.notEqual(values.owner_id,null);
                context.save().then(function(){
                    return tempContext.getObjectWithObjectID(car.objectID).then(function(tempCar){
                        values = tempCar.getValues();
                        //console.log(values,owner.id)
                        assert.equal(values.owner_id,car.getOwnerID());
                        assert.equal(values.owner_id,tempCar.getOwnerID());
                        done();
                    })
                }).catch(done)
            });

            it('shouldn\'t insert object before save is completed',function(done){
                var car = context.createObjectWithName('Car');
                context.save().then(function(){
                    assert.equal(car.objectID.isTemporaryID,false);
                    done();
                }).catch(done);
                assert.throws(function(){
                    context.createObjectWithName('Car');
                })
            });
            it('should insert self-reflexive relation',function(done){
                var owner = context.createObjectWithName('Owner');
                var owner2 = context.createObjectWithName('Owner');
                owner.addFriend(owner2);
                context.save().then(done).catch(done);
            });

            it('should insert two self-reflexive relations',function(done){
                var owner = context.createObjectWithName('Owner');
                var owner2 = context.createObjectWithName('Owner');
                owner.addEmployer(owner2);
                context.save(done);
            });

            it('should store object',function(done){
                var car = context.create('Car',{brand:'test car',timestamp:new Date(),date:new Date()});
                context.save(function(err){
                    assert.ifError(err);
                    var context2 = coreData.createContext();
                    context2.getObjectWithObjectID(car.objectID).then(function(car2){
                        assert.equal(car.timestamp.toString(),car2.timestamp.toString());
                        // console.log(JSON.stringify(car))
                        done();
                    }).catch(done)
                });
            });

            it('should get or create object',function(done){
                var brand = 'this is my car';
                var brand2 = 'this is my another car';
                context.getOrCreateObject('Car',{where:['SELF.brand = %s',brand]},{brand:brand},function(err,car){
                    assert.ifError(err);
                    assert.equal(car.brand,brand);
                    context.save(function(err){
                        assert.ifError(err);
                        context.getOrCreateObject('Car',{where:['SELF.brand = %s',brand]},{brand:brand2},function(err,car2){
                            assert.ifError(err);
                            assert.equal(car.brand,car2.brand);
                            done();
                        })
                    })
                })
            });

            it('should store object with default values',function(done){
                var car = context.create('Car');
                context.save(function(err){
                    assert.ifError(err);
                    assert.ok(car.uid);
                    tempContext = coreData.createContext();
                    tempContext.getObjectWithObjectID(car.objectID,function(err,car2){
                        assert.ifError(err);
                        assert.equal(car.uid,car2.uid);
                        tempContext.destroy();
                        done()
                    })
                })
            })

        });

        describe('intercontext stuff',function(){
            var context,context2,object;
            before(function(){
                context = coreData.createContext();
                context2 = coreData.createContext();
                object = context.createObjectWithName('Car');
            });

            it('should fail to insert object to another context',function(){
                assert.throws(function(){
                    context2.insertObject(object);
                })
            });
            it('should fail to delete object from another context',function(){
                assert.throws(function(){
                    context2.deleteObject(object);
                })
            });
        });


        describe('deletion', function(){
            var context;
            var object;

            before(function(done){
                context = coreData.createContext();
                context.getObjects('Car',function(err,cars){
//                    console.log('xxxx',cars);
                    if(err)throw err;
                    cars.forEach(function(car){
                        context.deleteObject(car);
                    })
                    object = context.createObjectWithName('Car');
                    context.save(function(err){
                        context.deleteObject(object);
                        done(err);
                    })
                })
            });

            after(function(done){
                context.save(function(err){
                    if(err)return done(err);
                    context.deleteObject(object);
                    context.saveAndDestroy(done);
                })
            });

            it('number of objects after create should be equal to 1', function(done){
                context.getObjects('Car',function(err,cars){
                    assert.equal(cars.length,1);
                    done();
                })
            });

            it('should set flag isDeleted of object to true',function(){
                assert.equal(true,object.isDeleted);
            });
            it('should have changes',function(){
                assert.equal(true,object.hasChanges);
            });
            it('number of objects after delete should be equal to zero', function(done){
                context.save(function(err){
                    assert.ifError(err);
                    context.getObjects('Car',function(err,cars){
                        assert.equal(cars.length,0);
                        done();
                    })
                })
            })
        });

        describe('error handling',function(){
            var context;

            before(function(){
                context = coreData.createContext();
            });

            it('should throw error when creating nonexisting object',function(){
                var entityName = 'NonExistent';
                assert.throws(function(){
                    context.createObjectWithName(entityName);
                },function(err){
                    return err.message == 'entity with name \'' + entityName + '\' doesn\'t exists';
                })
            })
        });

        describe('fetching',function(){
            var context;

            before(function(done){
                context = coreData.createContext();
                context.getObjects('Car',function(err,cars){
                    if(err)return done(err);
                    cars.forEach(function(car){context.deleteObject(car)});
                    context.save(function(err){
                        if(err)return done(err);
                        var car = context.createObjectWithName('Car');
                        car.brand = 'test';
                        var car2 = context.createObjectWithName('Car');
                        car2.brand = 'test2';
                        var owner = context.create('Owner',{name:'test',lastName:'test2'})
                        context.save(function(err){
                            done(err);
                        })
                    })
                })
            });
            after(function(done){
                context.getObjects('Car',function(err,objects){
                    assert.ifError(err);
                    objects.forEach(function(car){context.deleteObject(car)});
                    context.save(done);
                })
            });

            it('should load same instance in context',function(done){
                context.getObject('Car').then(function(car){
                    return context.getObject('Car').then(function(car2){
                        assert.ok(car === car2);
                        var oldBrand = car.brand
                        car.brand = 'xxx';
                        assert.equal(car2.brand,'xxx');
                        car.brand = oldBrand;
                        done();
                    });
                }).catch(done);
            });
            it('should load limited number of objects',function(done){
                context.getObjects('Car',{limit:1},function(err,objects){
                    assert.ifError(err);
                    assert.equal(objects.length,1);
                    done();
                })
            });
            it('should load offest objects',function(done){
                context.getObjects('Car',{offset:1,limit:2},function(err,objects){
                    assert.ifError(err);
                    assert.equal(objects.length,1);
                    done();
                })
            });
            it('should not load offest without limit',function(done){
                context.getObjects('Car',{offset:1},function(err,objects){
                    assert.ok(err !== null)
                    done()
                })
            });
            it('should add loaded objects to registered objects',function(done){
                context.getObjects('Car',function(err,objects){
                    assert.ifError(err);
                    objects.forEach(function(obj){
                        assert.notEqual(context.registeredObjects.indexOf(obj),-1);
                    });
                    done();
                })
            });
            it('should load all created objects',function(){
                context.getObjects('Car',function(err,cars){
                    assert.ifError(err);
                    assert.equal(cars.length,2);
                })
            });

            it('should load object by attribute(brand = \'test\')',function(done){
                context.getObjects('Car',{where:['SELF.brand = %s','test']},function(err,objects){
                    assert.ifError(err);
                    assert.equal(objects.length,1);
                    done();
                })
            });
            it('should load object by attribute(brand = \'test2\')',function(done){
                context.getObjects('Car',{where:['SELF.brand = %s','test2']},function(err,objects){
                    assert.ifError(err);
                    assert.equal(objects.length,1);
                    done();
                })
            });
            it('should load object by attribute(lastName = \'test2\')',function(done){
                context.getObjects('Owner',{where:['SELF.lastName = %s OR SELF.lastName = %s','test2','SELF.lastName']},function(err,objects){
                    assert.ifError(err);
                    assert.equal(objects.length,1);
                    done();
                })
            });
            it('should load object correctly sorted',function(done){
                context.getObjects('Car',{sort:'brand'},function(err,objects){
                    assert.ifError(err);
                    assert.equal(objects.length,2);
                    assert.equal(objects[0].brand,'test');
                    assert.equal(objects[1].brand,'test2');
                    done();
                })
            });
            it('should load object correctly sorted (descendant)',function(done){
                context.getObjects('Car',{sort:'-brand'},function(err,objects){
                    assert.ifError(err);
                    assert.equal(objects.length,2);
                    assert.equal(objects[0].brand,'test2');
                    assert.equal(objects[1].brand,'test');
                    done();
                })
            });
            it('should load same objects(uniquely)',function(done){
                var count = 10,loadedCount = 0;
                var objects = [];
                context.getObjects('Car',function(err,objs){
                    var obj = objs[0];
                    if(err)return done(err);
                    for(var i = 0;i<count;i++){
                        context.getObjectWithId(obj.entity.name,obj.objectID.recordId(),function(err,object){
                            objects.push(object);
                            if(++loadedCount == count){
                                objects.forEach(function(object){
                                    assert.ok(object === obj,'objects ('+object.objectID+' != '+obj.objectID+') aren\'t equal');
                                });
                                done();
                            }
                        })
                    }
                })
            });
            it('should load same objects from relation(uniquely)',function(done){
                var _context = coreData.createContext();
                var owner = context.createObjectWithName('Owner');
                var car = context.createObjectWithName('Car');
                //var car2 = context.createObjectWithName('Car');
                owner.addCar(car);
                context.save(function(err){
                    assert.ifError(err);
                    _context.getObjects('Car',function(err,_cars){
                        assert.ifError(err);
                        _context.getObjectWithObjectID(owner.objectID,function(err,_owner){
                            assert.ifError(err);
                            _owner.getCars().then(function(__cars){
                                assert.ok(__cars.length > 0,'object count');
                                var _car = __cars[0];
                                assert.ifError(err);
                                _cars.forEach(function(_c){
                                    assert.ok(_car.objectID.toString() != _c.objectID.toString() || _car === _c,_car.objectID.toString()+' == '+_c.objectID.toString()+' are not identical objects');
                                });
                                done()
                            }).catch(done)
                        })
                    })
                })
            });
            it('should load same objects in collection',function(done){
                context.getObjects('Car',{sort:'brand'},function(err,objects){
                    context.getObjects('Car',{sort:'brand'},function(err,objects2){
                        assert.equal(objects.length,objects2.length,'colletion count is not equal');
                        objects.forEach(function(obj,i){
                            assert.ok(obj === objects2[i],'objects aren\'t equal('+i+')');
                        });
                        done();
                    })
                })
            });
            it('should avoid loading same object twice when fetching concurrently',function(done){
                var array = [];
                var count = 100;
                function loaded(){
                    array[0].forEach(function(obj,i){
                        for(var x=0;x<count;x++){
                            assert.ok(obj === array[x][i],'objects aren\'t equal('+i+')');
                        }
                    });
                    done();
                }
                var loadedCount = 0;
                for(var x=0;x<count;x++){
                    context.getObjects('Car',{sort:'-brand'},function(err,objects){
                        array.push(objects);
                        if(++loadedCount == count)loaded();
                    })
                }
            });

            it('should get objects count',function(done){
                context.getObjects('Car',function(err,cars){
                    assert.ifError(err);
                    context.getObjectsCount('Car',function(err,count){
                        assert.ifError(err);
                        assert.equal(count,cars.length);
                        done();
                    })
                })
            });
            it('should get objects count with predicate',function(done){
                context.getObjects('Car',{where:['SELF.brand = %s','test']},function(err,cars){
                    assert.ifError(err);
                    context.getObjectsCount('Car',{where:['SELF.brand = %s','test']},function(err,count){
                        assert.ifError(err);
                        assert.equal(count,cars.length);
                        done();
                    })
                })
            })
        });

        describe('attributes',function(){
            var context,context2,car;
            before(function(){
                context = coreData.createContext();
                context2 = coreData.createContext();
                car = context.createObjectWithName("Car");
                car.brand = 'test car';
            });
            after(function(done){
                context.deleteObject(car);
                context.save(done);
            });

            it('should set flag isUpdated of object to true',function(){
                assert.equal(true,car.isUpdated);
            });
            it('should set flag hasChanges of object to true',function(){
                assert.equal(true,car.hasChanges);
            });
            it('should successfuly save attribute change',function(done){
                car.managedObjectContext.save(done);
            });
            it('should unset flag isUpdated of object to false after save',function(){
                assert.equal(false,car.isUpdated);
            });
            it('should unset flag hasChanges of object to false after save',function(){
                assert.equal(false,car.hasChanges);
            });

            it('should successfuly load changed attribute',function(done){
                context2.getObjectWithObjectID(car.objectID,function(err,_car){
                    if(err)return done(err);
                    assert.ok(_car);
                    assert.equal(car.brand,_car.brand);
                    done();
                })
            })
        });

        describe('relationships',function(){
            var context,context2;
            var car,owner,owner2;

            before(function(done){
                context = coreData.createContext();
                context2 = coreData.createContext();
                car = context.createObjectWithName('Car');
                car2 = context.createObjectWithName('Car');
                owner = context.createObjectWithName('Owner');
                owner.name = 'Jackie Prudil';
                owner2 = context.createObjectWithName('Owner');
//                console.log('owner',owner);
                context.save(done)
            });
            after(function(done){
                context.deleteObject(car);
                context.deleteObject(car2);
                context.deleteObject(owner);
                context.deleteObject(owner2);
                context.save(done);
            });
            describe('toOne',function(){
                it('should set single object for relation',function(done){
                    car.setOwner(owner);
                    assert.equal(car.getOwnerID(),owner.id)
                    car2.setOwner(null);
                    assert.equal(car2.getOwnerID(),null)
                    car2.setOwner(owner);
                    assert.equal(car2.getOwnerID(),owner.id)
                    car2.setOwner(owner2);
                    assert.equal(car2.getOwnerID(),owner2.id)
                    var owner3 = context.createObjectWithName('Owner');
                    car2.setOwner(owner3);
                    assert.equal(car2.getOwnerID(),owner3.id)
                    done();
                });
                it('should return array of assigned objects',function(done){
                    owner.getCars(function(err,cars){
                        if(err)return done(err);
//                        console.log('cars!!1',cars)
                        assert.equal(cars.length,2);
                        done();
                    })
                });
                it('should get objects from inversed relation',function(done){
                    owner.getCars(function(err,cars){
                        if(err)return done(err);
                        assert.ok(cars);
//                        console.log('cars!!',cars)
                        assert.notEqual(cars.indexOf(car),-1);
                        assert.notEqual(cars.indexOf(car2),-1);
                        done();
                    })
                });
                it('should get single object for relation',function(done){
                    car.getOwner(function(err,_owner){
                        if(err)return done(err);
                        owner2 = _owner;
                        done();
                    })
                });
                it('should return same object for relation',function(){
                    assert.equal(owner,owner2);
                });
                it('should save',function(done){
//                    console.log('saving car');
                    context.save(done);
                });
                it('should load relation object after saving',function(done){
                    context2.getObjectWithObjectID(car.objectID,function(err,_car){
                        if(err)return done(err);
                        _car.getOwner(function(err,_owner){
                            if(err)return done(err);
//                            console.log('!!',_car)
//                            console.log('_owner',_owner)
                            assert.ok(_owner);
                            assert.equal(owner._objectID.toString(),_owner._objectID.toString());
                            done();
                        })
                    })
                });
                it('should set null object and save',function(done){
                    car.setOwner(null);
                    context.save(done);
                });
                it('should load null after setting null',function(done){
                    car.getOwner(function(err,_owner){
                        assert.equal(_owner,null);
                        done(err);
                    })
                });
                it('should remove object from inversed relation after setting null',function(done){
                    owner.getCars(function(err,cars){
                        assert.equal(cars.indexOf(car),-1);
                        done(err);
                    })
                });
                it('should load null also from another context',function(done){
                    context2.reset();
//                    console.log('selecting car')
                    context2.getObjectWithObjectID(car.objectID,function(err,_car){
                        if(err)return done(err);
//                        console.log('getting owner')
                        _car.getOwner(function(err,_owner){
                            if(err)return done(err);
//                            console.log('owner get..',_owner)
                            assert.equal(!!_owner,false);
                            done();
                        })
                    })
                })
            });
            describe('toMany',function(){
                it('should add object to relation',function(){
                    owner.addCar(car);
                });
                it('given object; Owner=>cars',function(done){
                    car.getOwner(function(err,_owner){
                        if(err)return done(err);
                        assert.ok(_owner == owner);
                        done()
                    })
                });
                it('should save successfuly',function(done){
//                    console.log('saving')
                    context.save(done)
                });
                it('should get assigned object from another context',function(done){
                    context2.reset();
                    context2.getObjectWithObjectID(owner.objectID,function(err,_owner){
                        if(err)throw err;
//                        console.log('getting cars');
                        _owner.getCars(function(err,_cars){
                            if(err)return done(err);
                            var ids = [];
                            _cars.forEach(function(car){
                                ids.push(car.objectID.toString());
                            });
//                            console.log('cars!',car.objectID.toString());
                            assert.notEqual(ids.indexOf(car.objectID.toString()),-1);
                            done();
                        });
                    })
                });
                it('should get inversed assigned object from another context',function(done){
                    context2.reset();
                    context2.getObjectWithObjectID(car.objectID,function(err,_car){
                        assert.ok(_car);
                        if(err)return done(err);
                        car.getOwner(function(err,_owner){
                            if(err)return done(err);
                            assert.equal(_owner,owner);
                            done();
                        });
                    })
                });
                it('should get assigned object from another context',function(done){
                    owner.getCars(function(err,cars){
                        if(err)return done(err);
                        assert.notEqual(cars.indexOf(car),-1);
                        done();
                    });
                });
                it('should remove object from relation',function(){
                    owner.removeCar(car);
                });
                it('should assign reversed relation to null',function(done){
                    car.getOwner(function(err,_owner){
                        if(err)return done(err);
                        assert.ok(_owner == null);
                        done()
                    })
                });
                it('should save successfuly',function(done){
                    context.save(done)
                });
                it('should get unassigned object from another context',function(done){
                    context2.reset();
                    context2.getObjectWithObjectID(owner.objectID,function(err,_owner){
                        if(err)return done(err);
                        _owner.getCars(function(err,cars){
                            if(err)return done(err);
//                            console.log('cars xxx',cars)
                            assert.equal(cars.indexOf(car),-1);
                            done();
                        });
                    })
                })
            });
            describe('manyToMany',function(){
                var context = coreData.createContext()
                var owner,car;
                it('should create objects',function(done){
                    owner = context.create('Owner',{name:'test'})
                    car = context.create('Car',{name:'test'})
                    car.setOwner(owner)
                    context.save().then(function(){
                        done()
                    }).catch(done)
                })
                it('should add object to many-2-many',function(){
//                    console.log('assign visited car')
                    owner.addVisitedCar(car);
//                    console.log(owner._relationChanges);
//                    console.log(car._relationChanges);
                });
                it('should add object to many-2-many',function(done){
                    car.getVisitors(function(err,owners){
                        if(err)return done(err);
//                        console.log('!!!',owners,owner)
                        assert.notEqual(owners.indexOf(owner),-1);
                        done();
                    });
                });
                it('should get assigned object',function(done){
//                    console.log('get visited cars',owner.objectID.toString())
                    owner.getVisitedCars(function(err,visitedCars){
                        if(err)return done(err);
//                        console.log('viscars',visitedCars)
                        ids = [];
                        if(visitedCars)visitedCars.forEach(function(vc){
                            ids.push(vc.objectID.toString())
                        });
                        assert.notEqual(ids.indexOf(car.objectID.toString()),-1);
                        done();
                    })
                });
                it('should save successfully',function(done){
//                    console.log('saving')
                    context.save(done);
                });
                it('should get assigned objects from another context',function(done){
                    context2.reset();
                    context2.getObjectWithObjectID(owner.objectID,function(err,_owner){
                        _owner.getVisitedCars(function(err,visitedCars){
                            if(err)return done(err);
//                        console.log('viscars',visitedCars)
                            ids = [];
                            if(visitedCars)visitedCars.forEach(function(vc){
                                ids.push(vc.objectID.toString())
                            });
                            assert.notEqual(ids.indexOf(car.objectID.toString()),-1);
                            done();
                        })
                    })
                })
                it('should remove assigned objects',function(done){
//                    console.log('get visited cars',owner.objectID.toString())
                    owner.getVisitedCars(function(err,visitedCars){
                        if(err)return done(err);
                        owner.removeVisitedCars(visitedCars)
//                        console.log('viscars',visitedCars)
                        done();
                    })
                });
                it('should save successfully after removal',function(done){
//                    console.log('saving')
                    context.save(done);
                });
                it('should add object twice and save',function(done){
//                    console.log('assign visited car')
                    owner.addVisitedCar(car);
                    owner.managedObjectContext.save().then(function(){
                        owner.addVisitedCar(car);
                        owner.managedObjectContext.save(done);
                    }).catch(done);
//                    console.log(owner._relationChanges);
//                    console.log(car._relationChanges);
                });
                it('should add object to many-2-many repeatedle',function(done){
                    async.timesSeries(10,function(i,cb){
                        var context2 = coreData.createContext()
                        context2.getObjectWithObjectID(owner.objectID).then(function(owner2){
                            return context2.getObjectWithObjectID(car.objectID).then(function(car2) {
                                owner2.addVisitedCar(car2);
                                context2.save(cb)
                            })
                        }).catch(cb)
                    },done)
                });
            });
            describe('oneToOne',function(){
                before(function(done){
                    context.getObjects('Seller',function(err,objects){
                        assert.ifError(err);
                        objects.forEach(function(object){
                            context.deleteObject(object);
                        });
                        context.getObjects('Licence',function(err,objects){
                            assert.ifError(err);
                            objects.forEach(function(object){
                                context.deleteObject(object);
                            });
                            context.save(done);
                        })
                    })
                });
                var seller,licence;
                it('should assign oneToOne',function(done){
                    seller = context.createObjectWithName('Seller');
                    seller.name = 'test seller';

                    licence = context.createObjectWithName('Licence');

                    seller.setLicence(licence);

                    context.save(done)
                });
                it('should load assigned one to one objects',function(done){
                    context2.reset();
                    context2.getObjects('Seller',function(err,sellers){
                        assert.ifError(err);
                        var _seller = sellers[0];
                        assert.equal(_seller.objectID.toString(),seller.objectID.toString());
                        _seller.getLicence(function(err,_licence){
                            assert.ifError(err);
                            assert.equal(_licence.objectID.toString(),licence.objectID.toString());
                            done();
                        })
                    })
                });
                it('should load assigned one to one objects',function(done){
                    context2.reset();
                    context2.getObjects('Licence',function(err,licences){
                        assert.ifError(err);
                        var _licence = licences[0];
                        assert.equal(_licence.objectID.toString(),licence.objectID.toString());
                        _licence.getSeller(function(err,_seller){
                            assert.ifError(err);
                            assert.equal(_seller.objectID.toString(),seller.objectID.toString());
                            done();
                        })
                    })
                })
            })
        })
    })
});
