var assert = require("assert"),
    ManagedObjectModel = require('./../lib/ManagedObjectModel'),
    ManagedObjectContext = require('./../lib/ManagedObjectContext'),
    PersistentStoreCoordinator = require('./../lib/PersistentStoreCoordinator'),
    ModelYamlParser = require('../lib/Parsers/ModelYamlParser')
    moment = require('moment'),
    CoreData = require('../'),
    fs = require('fs');

var store_url = require('./get_storage_url');

describe('ManagedObject',function(){
    describe('attributes',function(){
        var objectModel = new ManagedObjectModel();
        ModelYamlParser.fillModelFromYaml(objectModel,fs.readFileSync(__dirname + '/schemes/object-test-model.yaml'),{Hello: require('./Classes/Hello')})
//        var invalidObjectModel = new ManagedObjectModel(__dirname + '/schemes/attribute-invalid-test-model.yaml');

        it('should throw error for invalid model',function(){
            assert.throws(function(){
                new ManagedObjectModel();
                ModelYamlParser.fillModelFromYaml(objectModel,fs.readFileSync(__dirname + '/schemes/attribute-invalid-test-model.yaml'))
            },/unknown attribute type/);
//            storeCoordinator = new PersistentStoreCoordinator(invalidObjectModel,{logging:console.log});
//
//            storeCoordinator.addStore(store_url);
//            storeCoordinator.persistentStores[0].syncSchema({force:true},function(err){
//                console.log(err)
//                assert.throws(function(){
//                    if(err)throw err;
//                },function(err){
//                    return err.message == 'unknown attribute type blah';
//                })
//                done()
//            })
        });
        it('shouldn\'t throw error for valid model',function(){
            storeCoordinator = new PersistentStoreCoordinator(objectModel);

            store = storeCoordinator.addStore(store_url);
            return storeCoordinator.persistentStores[0].syncSchema({force:true})
        });
        describe('validation',function(){
            var storeCoordinator,timestamp = Date.now();
            var date = new Date(Math.round(timestamp/1000)*1000);
            var transformableObject = {aa:'bb',date:(new Date())};
            var transformableArray = [{aa:'bb',date:(new Date())}];
            function deleteAll(storeCoordinator,done){
                var context = new ManagedObjectContext(storeCoordinator);
                context.getObjects('Hello',function(err,objects){
                    if(err)return done(err);
                    objects.forEach(function(obj){
                        context.deleteObject(obj);
                    });
                    context.save(done);
                })
            }
            before(function(done){
                storeCoordinator = new PersistentStoreCoordinator(objectModel,{logging:false});
                storeCoordinator.addStore(store_url);
                //storeCoordinator.persistentStores[0].globals.logging = console.log
                storeCoordinator.persistentStores[0].syncSchema({force:true}).then(function(){
                    deleteAll(storeCoordinator,done);
                }).catch(done)
            });
    //        after(function(done){
    //            deleteAll(storeCoordinator,done);
    //        })


            it('should assign only allowed attributes',function(){
                var context = new ManagedObjectContext(storeCoordinator);
                var obj = context.createObjectWithName('Hello');
                obj.setValues({
                    int:123,
                    bool:true
                },['int']);
                assert.equal(obj.int,123);
                assert.equal(obj.bool,null)
            });

            it('should assign only allowed attributes',function(){
                var context = new ManagedObjectContext(storeCoordinator);
                var obj = context.createObjectWithName('Hello');
                obj.setValues({
                    int:123,
                    bool:true
                });
                var values = obj.getValues(['int']);
                assert.equal(values.int,123);
                assert.equal(values.bool,null)
            });

            it('should create object and assign all valid values',function(done){
                var context = new ManagedObjectContext(storeCoordinator);
                var obj = context.createObjectWithName('Hello');
                assert.doesNotThrow(function(){
                    obj.bool = true;
                    obj.bool = 1;
                    obj.name = 'test';
                    obj.int = 1004;
                    obj.decim = 0.55;
                    obj.float = 10.505;
                    obj.double = 100.5054;
                    obj.email = 'jackie@gmail.com';
                    obj.url = 'http://www.google.com';
                    obj.enum = 'a';
                    obj.enum = 'b';
                    obj.enum = 'c';
                    obj.date = date;
                    obj.timestamp = timestamp;
                    obj.transformable = transformableObject;
                    obj.transformableArray = transformableArray;
                });
                context.save(done);
            });
            it('should create object with all null values',function(){
                var context = new ManagedObjectContext(storeCoordinator);
                var obj = context.create('Hello',{name:null,date:null,timestamp:null});
                assert.strictEqual(obj.bool,null,'bool value');
                assert.strictEqual(obj.name,null);
                assert.strictEqual(obj.int,null);
                assert.strictEqual(obj.decim,null);
                assert.strictEqual(obj.float,null);
                assert.strictEqual(obj.double,null);
                assert.strictEqual(obj.email,null);
                assert.strictEqual(obj.url,null);
                assert.equal(obj.date,null);
                assert.equal(obj.enum,null);
                assert.equal(obj.timestamp,null);
                assert.equal(obj.transformable,null);
                assert.equal(obj.transformableArray,null);
                assert.equal(obj.getWorldID(),null);
            });
            it('should load all attributes',function(done){
                var context = new ManagedObjectContext(storeCoordinator);
                context.getObjects('Hello',function(err,objects){
                    if(err)return done(err);
                    var obj = objects[0];
                    assert.equal(obj.awakeFromFetchValue,'fetched');
                    assert.strictEqual(obj.bool,true,'bool value');
                    assert.strictEqual(obj.name,'test');
                    assert.strictEqual(obj.int,1004);
                    assert.strictEqual(obj.decim,0.55);
                    assert.strictEqual(obj.float,10.505);
                    assert.strictEqual(obj.double,100.5054);
                    assert.strictEqual(obj.email,'jackie@gmail.com');
                    assert.strictEqual(obj.url,'http://www.google.com');
                    assert.strictEqual(obj.enum,'c');
                    assert.equal(obj.date.toISOString(),date.toISOString(),'date doesnt match');
                    assert.equal(obj.timestamp.toISOString(),(new Date(timestamp)).toISOString());
                    assert.equal(JSON.stringify(obj.transformable),JSON.stringify(transformableObject));
                    assert.equal(JSON.stringify(obj.transformableArray),JSON.stringify(transformableArray));
                    assert.equal(obj.getWorldID(),null);
                    done();
                })
            });
            it('should load null attributes',function(done){
                var context = new ManagedObjectContext(storeCoordinator);
                context.create('Hello',{name:null,date:null,timestamp:null})
                context.save().then(function(){
                    context.getObject('Hello',{where:['SELF.bool IS NULL']}).then(function(obj){
                        assert.strictEqual(obj.bool,null,'bool value');
                        assert.strictEqual(obj.name,null);
                        assert.strictEqual(obj.int,null);
                        assert.strictEqual(obj.decim,null);
                        assert.strictEqual(obj.float,null);
                        assert.strictEqual(obj.double,null);
                        assert.strictEqual(obj.email,null);
                        assert.strictEqual(obj.url,null);
                        assert.equal(obj.date,null);
                        assert.equal(obj.timestamp,null);
                        assert.equal(obj.transformable,null);
                        assert.equal(obj.transformableArray,null);
                        assert.equal(obj.getWorldID(),null);
                        done();
                    }).catch(done)
                }).catch(done)

            });
            it('should create object and assign all valid values from object',function(done){
                var context = new ManagedObjectContext(storeCoordinator);
                var obj = context.createObjectWithName('Hello');
                assert.doesNotThrow(function(){
                    obj.setValues({
                        bool:true,
                        name:'test',
                        int:1004,
                        decim: 0.55,
                        float: 10.505,
                        double: 100.5054,
                        email:'jackie@gmail.com',
                        url:'http://www.google.com',
                        timestamp: timestamp,
                        transformable: transformableObject,
                        transformableArray: transformableArray,
                        enum:'a'
                    })
                });
                context.save(done);
            });
            it('should load all attributes from persistent store',function(done){
                var context = new ManagedObjectContext(storeCoordinator);
                context.getObjects('Hello',function(err,objects){
                    if(err)return done(err);
                    var obj = objects[0];
                    assert.strictEqual(obj.bool,true);
                    assert.strictEqual(obj.name,'test');
                    assert.strictEqual(obj.int,1004);
                    assert.strictEqual(obj.decim,0.55);
                    assert.strictEqual(obj.float,10.505);
                    assert.strictEqual(obj.double,100.5054);
                    assert.strictEqual(obj.email,'jackie@gmail.com');
                    assert.strictEqual(obj.url,'http://www.google.com');
                    assert.strictEqual(obj.enum,'c');
                    assert.equal(obj.date.toISOString(),date.toISOString());
                    assert.equal(obj.timestamp.toISOString(),(new Date(timestamp)).toISOString());
                    assert.equal(JSON.stringify(obj.transformable),JSON.stringify(transformableObject));
                    assert.equal(JSON.stringify(obj.transformableArray),JSON.stringify(transformableArray));
                    done();
                })
            });
            it('shouldn\'t assign (in)valid date value',function(){
                var context = new ManagedObjectContext(storeCoordinator);
                var obj = context.createObjectWithName('Hello');
                assert.throws(function(){
                    obj.date = 'this is not valid date';
                },'invalid string to date');
                assert.throws(function(){
                    obj.date = 25; //this also
                },'integer to date');
                assert.doesNotThrow(function(){
                    obj.date = null;
                });
                assert.doesNotThrow(function(){
                    obj.date = new Date();
                });
                assert.doesNotThrow(function(){
                    obj.date = (new Date()).toISOString();
                })
            });
            it('should transform date value from various formats',function(){
                var context = new ManagedObjectContext(storeCoordinator);
                var obj = context.createObjectWithName('Hello');

                var date = new Date(Math.floor(Date.now()/1000)*1000);

                var formats = {};

                formats.isoFormat = date.toISOString();
                formats.nativeStringFormat = date.toString();
                formats.ddmmyyFormat = moment(date).format('YYYY-MM-DD HH:mm:ss');
                formats.ddmmyyFormatDashes = moment(date).format('YYYY/MM/DD HH:mm:ss');
                for(var i in formats){
                    if (formats.hasOwnProperty(i)) {
                        var _d = formats[i];
                        assert.doesNotThrow(function () {
                            obj.date = _d;
                        }, i);
                        assert.equal(obj.date.toISOString(), date.toISOString(), 'format '+i+'('+obj.date+')');
                    }
                }
            });
            it('shouldn\'t pass invalid string',function(){
                var context = new ManagedObjectContext(storeCoordinator);
                var obj = context.createObjectWithName('Hello');

                assert.throws(function(){
                    obj.shortString = '01234567890123456789' + '0';//max length is 20
                },'too long');
                assert.throws(function(){
                    obj.shortString = 'a';//max length is 20
                },'too short');
                assert.throws(function(){
                    obj.shortString = 'aAb';//max length is 20
                },'does not pass RegExp aAb');
                assert.throws(function(){
                    obj.shortString = 'aBb';//max length is 20
                },'does not pass RegExp aBb');
                assert.doesNotThrow(function(){
                    obj.shortString = 'aa';
                });
                assert.doesNotThrow(function(){
                    obj.shortString = 'aaaa';
                })
            });
            it('should pass invalid int',function(){
                var context = new ManagedObjectContext(storeCoordinator);
                var obj = context.createObjectWithName('Hello');

                assert.throws(function(){
                    obj.int = 1;
                },'min is 2');
                assert.throws(function(){
                    obj.int = 1010;
                },'max is 1005');
                assert.doesNotThrow(function(){
                    obj.int = 1005;
                });
                assert.doesNotThrow(function(){
                    obj.int = 1000;
                });
                assert.doesNotThrow(function(){
                    obj.int = null;
                });
            });
            it('should pass invalid float',function(){
                var context = new ManagedObjectContext(storeCoordinator);
                var obj = context.createObjectWithName('Hello');

                assert.throws(function(){
                    obj.float = 2.4;
                },'min is 2.5');
                assert.throws(function(){
                    obj.float = 5000.9;
                },'max is 5000.8');
                assert.throws(function(){
                    obj.float = 5158;
                });
                assert.doesNotThrow(function(){
                    obj.float = 5000.8;
                });
                assert.doesNotThrow(function(){
                    obj.float = 4;
                });
                assert.doesNotThrow(function(){
                    obj.float = null;
                });
            });

            it('should pass valid url',function(){
                var context = new ManagedObjectContext(storeCoordinator);
                var obj = context.createObjectWithName('Hello');

                assert.throws(function(){
                    obj.url = 'aa';
                });
                assert.throws(function(){
                    obj.url = 'http://';
                });
                assert.throws(function(){
                    obj.url = 'www.google.com';
                });
                assert.throws(function(){
                    obj.url = 'sfgsg://www.google.com/aadfsdg';
                });
                assert.throws(function(){
                    obj.setValues({url:'sfgsg://www.google.com/aadfsdg'});
                });
                assert.doesNotThrow(function(){
                    obj.url = 'http://www.google.com';
                });
                assert.doesNotThrow(function(){
                    obj.url = 'http://www.google.com/myfile';
                });
                assert.doesNotThrow(function(){
                    obj.url = 'ftp://www.google.com/test/com.abcd';
                });
                assert.doesNotThrow(function(){
                    obj.url = 'ftp://www.google.com/test/com.abcd?testmy&arg2=a';
                });
                assert.doesNotThrow(function(){
                    obj.setValues({url:'ftp://www.google.com/test/com.abcd?testmy&arg2=a'});
                });
                assert.doesNotThrow(function(){
                    obj.url = 'http://john:doe@www.google.com';
                })
            });
            it('should pass valid email',function(){
                var context = new ManagedObjectContext(storeCoordinator);
                var obj = context.createObjectWithName('Hello');

                assert.throws(function(){
                    obj.email = 'aa';
                });
                assert.throws(function(){
                    obj.email = 'invalid email';
                });
                assert.throws(function(){
                    obj.email = 'j@d.com';
                });
                assert.throws(function(){
                    obj.email = 'john@doe.';
                });
                assert.throws(function(){
                    obj.setValues({email:'john@doe.'});
                });
                assert.doesNotThrow(function(){
                    obj.email = 'john@doe.com';
                });
                assert.doesNotThrow(function(){
                    obj.email = 'jo.hn.do.e@doe.com';
                });
                assert.doesNotThrow(function(){
                    obj.email = 'john.doe@gmail.com';
                })
            });
            it('should pass valid number',function(){
                var context = new ManagedObjectContext(storeCoordinator);
                var obj = context.createObjectWithName('Hello');

                // double
                assert.throws(function(){
                    obj.double = 'aa';
                });
                assert.doesNotThrow(function(){
                    obj.double = 25.6134;
                });
                assert.doesNotThrow(function(){
                    obj.double = '1.5';
                });
                assert.strictEqual(obj.double,1.5);
                // float
                assert.throws(function(){
                    obj.float = 'aa';
                });
                assert.doesNotThrow(function(){
                    obj.float = 25.6134;
                });
                assert.doesNotThrow(function(){
                    obj.float = '2.5';
                });
                assert.strictEqual(obj.float,2.5);
                // int
                assert.throws(function(){
                    obj.int = 'aa';
                });
                assert.throws(function(){
                    obj.int = '25.689';
                });
                assert.throws(function(){
                    obj.setValues({int:'25.689'});
                });
                assert.doesNotThrow(function(){
                    obj.int = 25;
                });
                assert.doesNotThrow(function(){
                    obj.int = '155';
                });
                assert.strictEqual(obj.int,155);
            });
            it('should pass valid boolean',function(){
                var context = new ManagedObjectContext(storeCoordinator);
                var obj = context.createObjectWithName('Hello');

                // double
                assert.throws(function(){
                    obj.bool = 'aa';
                });
                assert.throws(function(){
                    obj.bool = 'my false';
                });
                assert.throws(function(){
                    obj.setValues({bool:'my false'});
                });
                assert.doesNotThrow(function(){
                    obj.bool = true;
                });
                assert.doesNotThrow(function(){
                    obj.bool = false;
                });
                assert.doesNotThrow(function(){
                    obj.bool = 'false';
                });
                assert.strictEqual(obj.bool,false);
                assert.doesNotThrow(function(){
                    obj.bool = 'true';
                });
                assert.strictEqual(obj.bool,true);
                assert.doesNotThrow(function(){
                    obj.bool = 'on';
                });
                assert.strictEqual(obj.bool,true);
                assert.doesNotThrow(function(){
                    obj.bool = '1';
                });
                assert.strictEqual(obj.bool,true);
            })
            it('should pass valid enum',function(){
                var context = new ManagedObjectContext(storeCoordinator);
                var obj = context.createObjectWithName('Hello');

                assert.throws(function(){
                    obj.enum = 'aa';
                });
                assert.throws(function(){
                    obj.enum = 'xx';
                });
                assert.throws(function(){
                    obj.enum = false;
                });
                assert.throws(function(){
                    obj.enum = true;
                });
                assert.throws(function(){
                    obj.enum = 125;
                },/invalid value .+ for attribute enum \(possible values: a, b, c\)/);
                assert.throws(function(){
                    obj.enum = {adg:'adf'};
                });
                assert.throws(function(){
                    obj.setValues({enum:25});
                });
                assert.doesNotThrow(function(){
                    obj.enum = null;
                });
                assert.strictEqual(obj.enum,null);
                assert.doesNotThrow(function(){
                    obj.enum = 'a';
                });
                assert.strictEqual(obj.enum,'a');
                assert.doesNotThrow(function(){
                    obj.enum = 'b';
                });
                assert.strictEqual(obj.enum,'b');
                assert.doesNotThrow(function(){
                    obj.enum = 'c';
                });
                assert.strictEqual(obj.enum,'c');
            })
            it('private attribute',function(){
                var context = new ManagedObjectContext(storeCoordinator);
                var obj = context.createObjectWithName('Hello');

                assert.ok(obj.entity.getAttribute('privateAttribute').isPrivate())

                assert.equal(obj.getValues().privateAttribute,undefined)
                assert.equal(obj.privateAttribute,'this is private!')

                obj.setValues({privateAttribute:'new Value'})
                assert.equal(obj.getValues().privateAttribute,undefined)
                assert.equal(obj.privateAttribute,'this is private!')

                obj.privateAttribute = 'new Value';
                assert.equal(obj.getValues({privates:true}).privateAttribute,'new Value')
                assert.equal(obj.privateAttribute,'new Value')

                obj.setValues({privateAttribute:'new Value2'},{privates:true})
                assert.equal(obj.privateAttribute,'new Value2')

                obj = context.create('Hello',{privateAttribute:'xxx'})
                assert.equal(obj.privateAttribute,'this is private!')

                obj = context.create('Hello',{privateAttribute:'xxx'},{privates:true})
                assert.equal(obj.privateAttribute,'xxx')

                obj.setValues({privateAttribute:'yyy'},['privateAttribute'])
                assert.equal(obj.privateAttribute,'yyy')
            })
            it('should persist/load private attributes',function(done){
                var context = new ManagedObjectContext(storeCoordinator);
                var context2 = new ManagedObjectContext(storeCoordinator);

                obj = context.create('Hello',{privateAttribute:'xxx'},{privates:true})
                context.save().then(function(){
                    return context2.getObjectWithObjectID(obj.objectID).then(function(obj2){
                        assert.equal(obj2.privateAttribute,obj.privateAttribute)
                        done()
                    })
                }).catch(done)
            })
            it('transient attribute',function(done){
                var context = new ManagedObjectContext(storeCoordinator);
                var obj = context.createObjectWithName('Hello');


                assert.equal(obj.fullName,obj.firstname + ' ' + obj.lastname)

                obj.firstname += '2'
                obj.lastname += '2'
                assert.equal(obj.fullName,obj.firstname + ' ' + obj.lastname)

                obj.fullName = 'Siri Smith'
                assert.equal(obj.firstname,'Siri')
                assert.equal(obj.lastname,'Smith')

                obj.fullName2 = 'test test'
                context.save(done)
            })
            it('should persist object with transient attribute',function(done){
                var context = new ManagedObjectContext(storeCoordinator);
                var context2 = new ManagedObjectContext(storeCoordinator);
                var obj = context.createObjectWithName('Hello');


                obj.fullName = 'Siri Smith'
                assert.equal(obj.firstname,'Siri')
                assert.equal(obj.lastname,'Smith')

                context.save().then(function(){
                    return context2.getObjectWithObjectID(obj.objectID).then(function(obj2){
                        assert.equal(obj.fullName,obj2.fullName)
                        done()
                    })
                }).catch(done)
            })
        });
        describe('custom type',function(){
            CoreData.registerType(new CoreData.AttributeType('blah','string'));
            var db = new CoreData(store_url);
            db.defineEntity('Blah',{
                blahAttr:{
                    type:'blah',
                    default:'xxx'
                }
            });

            var context = db.createContext();

            var b = context.create('Blah');

            assert.equal(b.blahAttr,'xxx');
        })
    });

    describe('lifecycle',function(){
        it('should create object with default values',function(){
            var context = new ManagedObjectContext(storeCoordinator);
            var obj = context.createObjectWithName('Hello');
            assert.equal(obj.name,'defVal');
            assert.notEqual(obj.date,null);
            assert.equal(obj.awakeFromInsertValue,'awaken');
        });
        it('should call willSave',function(done){
            var context = new ManagedObjectContext(storeCoordinator);
            var obj = context.createObjectWithName('Hello');
            context.save().then(function(){
                assert.equal(obj.saveValue,'did save');
                done()
            }).catch(done);
            assert.equal(obj.saveValue,'will save');
        });
    })

    describe('relationships',function(){
        before(function(done){
            coreData = new CoreData(store_url,{
                logging:false
            });
            coreData.createModelFromYaml(fs.readFileSync(__dirname + '/schemes/car-model.yaml'))
            coreData.syncSchema({force:true}).then(done,done);
        });


        it('shouldn\'t set anything else than valid ManagedObject for relation',function(){
            var context = coreData.createContext();
            var car = context.create('Car');
            [undefined,'adfa',134].forEach(function(value){
                assert.throws(function(){
                    car.setOwner(value);
                },/only ManagedObject instances or null/)
            })
        });


        it('shouldn\'t add anything else than object to relation',function(){
            var context = coreData.createContext();
            var owner = context.create('Owner');

            assert.throws(function(){
                owner.addCar(null);
            },/only ManagedObject instances/);
            assert.throws(function(){
                owner.addCars(null);
            },/array must be specified in addObjects/);
            assert.throws(function(){
                owner.addCars([null]);
            },/only ManagedObject instances can be added/)
        });
    })

    describe('script created model',function(){
        var database = new CoreData('sqlite://:memory:')
        before(function(done){
            database.defineEntity('User',{
                username: 'string',
                number: {
                    type: 'int',
                    default: 0
                },
                int: {
                    type: 'int',
                    default: 0
                },
                bool: {
                    type: 'bool',
                    default: false
                }
            });
            database.syncSchema({force:true},done);
        })

        it('should initialize object',function(){
            var context = database.createContext();
            var obj = context.create('User');

            assert.strictEqual(obj.int,0);
            assert.strictEqual(obj.bool,false);
        })
    })
});
