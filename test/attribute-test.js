var assert = require("assert"),
    ManagedObjectModel = require('./../lib/ManagedObjectModel'),
    ManagedObjectContext = require('./../lib/ManagedObjectContext'),
    PersistentStoreCoordinator = require('./../lib/PersistentStoreCoordinator'),
    moment = require('moment');

//var store_url = 'mysql://root@localhost/test';
var store_url = 'sqlite://:memory:';

describe('attributes',function(){
    var objectModel = new ManagedObjectModel(__dirname + '/schemes/attribute-test-model.yaml');
    var invalidObjectModel = new ManagedObjectModel(__dirname + '/schemes/attribute-invalid-test-model.yaml');
//    before(function(done){
//    })
    it('should throw error for invalid model',function(done){
        storeCoordinator = new PersistentStoreCoordinator(invalidObjectModel);

        storeCoordinator.addStore(store_url);
        storeCoordinator.persistentStores[0].syncSchema({force:true},function(err){
            assert.throws(function(){
                if(err)throw err;
            },function(err){
                return err.message == 'unknown attribute type blah';
            })
            done()
        })
    })
    it('shouldn\'t throw error for valid model',function(done){
        storeCoordinator = new PersistentStoreCoordinator(objectModel);

        storeCoordinator.addStore(store_url);
        storeCoordinator.persistentStores[0].syncSchema({force:true},function(err){
            assert.ifError(err);
            done()
        })
    })
    describe('validation',function(){
        var storeCoordinator,timestamp = Math.round(Date.now() / 1000);
        var date = new Date(timestamp*1000);
        var transformableObject = {aa:'bb',date:(new Date())}
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
            })
        })
//        after(function(done){
//            deleteAll(storeCoordinator,done);
//        })

        it('should create object with default values',function(){
            var context = new ManagedObjectContext(storeCoordinator)
            var obj = context.createObjectWithName('Hello')
//            console.log(obj)
            assert.equal(obj.name,'defVal')

        })

        it('should create object and assign all valid values',function(done){
            var context = new ManagedObjectContext(storeCoordinator)
            var obj = context.createObjectWithName('Hello')
            assert.doesNotThrow(function(){
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
                obj.transformable = transformableObject;
            })
            context.save(done);
        })
        it('should load all attributes',function(done){
            var context = new ManagedObjectContext(storeCoordinator)
            context.getObjects('Hello',function(err,objects){
                if(err)return done(err);
                var obj = objects[0];
                assert.strictEqual(obj.bool,true,'bool value');
                assert.strictEqual(obj.name,'test');
                assert.strictEqual(obj.int,1600);
                assert.strictEqual(obj.decim,0.55);
                assert.strictEqual(obj.float,10.505);
                assert.strictEqual(obj.double,100.5054);
                assert.strictEqual(obj.email,'jackie@gmail.com');
                assert.strictEqual(obj.url,'http://www.google.com');
                assert.equal(obj.date.toISOString(),date.toISOString())
                assert.equal(obj.timestamp.toISOString(),(new Date(timestamp)).toISOString())
                assert.equal(JSON.stringify(obj.transformable),JSON.stringify(transformableObject))
                assert.equal(obj.getWorldID(),null)
                done();
            })
        })
        it('should create object and assign all valid values from object',function(done){
            var context = new ManagedObjectContext(storeCoordinator)
            var obj = context.createObjectWithName('Hello')
            assert.doesNotThrow(function(){
                obj.setValues({
                    bool:true,
                    name:'test',
                    int:1600,
                    decim: 0.55,
                    float: 10.505,
                    double: 100.5054,
                    email:'jackie@gmail.com',
                    url:'http://www.google.com',
                    timestamp: timestamp,
                    transformable: transformableObject
                })
            })
            context.save(done);
        })
        it('should load all attributes from persistent store',function(done){
            var context = new ManagedObjectContext(storeCoordinator)
            context.getObjects('Hello',function(err,objects){
                if(err)return done(err);
                var obj = objects[0];
                assert.strictEqual(obj.bool,true);
                assert.strictEqual(obj.name,'test');
                assert.strictEqual(obj.int,1600);
                assert.strictEqual(obj.decim,0.55);
                assert.strictEqual(obj.float,10.505);
                assert.strictEqual(obj.double,100.5054);
                assert.strictEqual(obj.email,'jackie@gmail.com');
                assert.strictEqual(obj.url,'http://www.google.com');
                assert.equal(obj.date.toISOString(),date.toISOString())
                assert.equal(obj.timestamp.toISOString(),(new Date(timestamp)).toISOString())
                assert.equal(JSON.stringify(obj.transformable),JSON.stringify(transformableObject))
                done();
            })
        })
        it('shouldn\'t assign (in)valid date value',function(){
            var context = new ManagedObjectContext(storeCoordinator)
            var obj = context.createObjectWithName('Hello')
            assert.throws(function(){
                obj.date = 'this is not valid date';
            },'invalid string to date')
            assert.throws(function(){
                obj.date = 25; //this also
            },'integer to date')
            assert.doesNotThrow(function(){
                obj.date = null;
            })
            assert.doesNotThrow(function(){
                obj.date = new Date();
            })
            assert.doesNotThrow(function(){
                obj.date = (new Date()).toISOString();
            })
        })
        it('should transform date value from various formats',function(){
            var context = new ManagedObjectContext(storeCoordinator)
            var obj = context.createObjectWithName('Hello')

            var date = new Date(Math.floor(Date.now()/1000)*1000);

            var formats = {};

            formats.isoFormat = date.toISOString()
            formats.nativeStringFormat = date.toString()
            formats.ddmmyyFormat = moment(date).format('YYYY-MM-DD HH:mm:ss');
            formats.ddmmyyFormatDashes = moment(date).format('YYYY/MM/DD HH:mm:ss');
            for(var i in formats){
                var _d = formats[i];
                assert.doesNotThrow(function(){
                    obj.date = _d;
                },i)
                assert.equal(obj.date.toISOString(),date.toISOString(),'format');
            }
        })
        it('shouldn\'t pass invalid string',function(){
            var context = new ManagedObjectContext(storeCoordinator)
            var obj = context.createObjectWithName('Hello')

            assert.throws(function(){
                obj.shortString = '01234567890123456789' + '0';//max length is 20
            },'too long')
            assert.throws(function(){
                obj.shortString = 'a';//max length is 20
            },'too short')
            assert.throws(function(){
                obj.shortString = 'aAb';//max length is 20
            },'does not pass RegExp aAb')
            assert.throws(function(){
                obj.shortString = 'aBb';//max length is 20
            },'does not pass RegExp aBb')
            assert.doesNotThrow(function(){
                obj.shortString = 'aa';
            })
            assert.doesNotThrow(function(){
                obj.shortString = 'aaaa';
            })
        })
        it('should pass valid url',function(){
            var context = new ManagedObjectContext(storeCoordinator)
            var obj = context.createObjectWithName('Hello')

            assert.throws(function(){
                obj.url = 'aa';
            })
            assert.throws(function(){
                obj.url = 'http://';
            })
            assert.throws(function(){
                obj.url = 'www.google.com';
            })
            assert.throws(function(){
                obj.url = 'sfgsg://www.google.com/aadfsdg';
            })
            assert.throws(function(){
                obj.setValues({url:'sfgsg://www.google.com/aadfsdg'});
            })
            assert.doesNotThrow(function(){
                obj.url = 'http://www.google.com';
            })
            assert.doesNotThrow(function(){
                obj.url = 'http://www.google.com/myfile';
            })
            assert.doesNotThrow(function(){
                obj.url = 'ftp://www.google.com/test/com.abcd';
            })
            assert.doesNotThrow(function(){
                obj.url = 'ftp://www.google.com/test/com.abcd?testmy&arg2=a';
            })
            assert.doesNotThrow(function(){
                obj.setValues({url:'ftp://www.google.com/test/com.abcd?testmy&arg2=a'});
            })
            assert.doesNotThrow(function(){
                obj.url = 'http://john:doe@www.google.com';
            })
        })
        it('should pass valid email',function(){
            var context = new ManagedObjectContext(storeCoordinator)
            var obj = context.createObjectWithName('Hello')

            assert.throws(function(){
                obj.email = 'aa';
            })
            assert.throws(function(){
                obj.email = 'invalid email';
            })
            assert.throws(function(){
                obj.email = 'j@d.com';
            })
            assert.throws(function(){
                obj.email = 'john@doe.';
            })
            assert.throws(function(){
                obj.setValues({email:'john@doe.'});
            })
            assert.doesNotThrow(function(){
                obj.email = 'john@doe.com';
            })
            assert.doesNotThrow(function(){
                obj.email = 'jo.hn.do.e@doe.com';
            })
            assert.doesNotThrow(function(){
                obj.email = 'john.doe@gmail.com';
            })
        })
        it('should pass valid number',function(){
            var context = new ManagedObjectContext(storeCoordinator)
            var obj = context.createObjectWithName('Hello')

            // double
            assert.throws(function(){
                obj.double = 'aa';
            })
            assert.doesNotThrow(function(){
                obj.double = 25.6134;
            })
            assert.doesNotThrow(function(){
                obj.double = '1.5';
            })
            assert.strictEqual(obj.double,1.5);
            // float
            assert.throws(function(){
                obj.float = 'aa';
            })
            assert.doesNotThrow(function(){
                obj.float = 25.6134;
            })
            assert.doesNotThrow(function(){
                obj.float = '1.5';
            })
            assert.strictEqual(obj.float,1.5);
            // int
            assert.throws(function(){
                obj.int = 'aa';
            })
            assert.throws(function(){
                obj.int = '25.689';
            })
            assert.throws(function(){
                obj.setValues({int:'25.689'});
            })
            assert.doesNotThrow(function(){
                obj.int = 25;
            })
            assert.doesNotThrow(function(){
                obj.int = '155';
            })
            assert.strictEqual(obj.int,155);
        })
        it('should pass valid boolean',function(){
            var context = new ManagedObjectContext(storeCoordinator)
            var obj = context.createObjectWithName('Hello')

            // double
            assert.throws(function(){
                obj.bool = 'aa';
            })
            assert.throws(function(){
                obj.bool = 'my false';
            })
            assert.throws(function(){
                obj.setValues({bool:'my false'});
            })
            assert.doesNotThrow(function(){
                obj.bool = true;
            })
            assert.doesNotThrow(function(){
                obj.bool = false;
            })
            assert.doesNotThrow(function(){
                obj.bool = 'false';
            })
            assert.strictEqual(obj.bool,false);
            assert.doesNotThrow(function(){
                obj.bool = 'true';
            })
            assert.strictEqual(obj.bool,true);
            assert.doesNotThrow(function(){
                obj.bool = 'on';
            })
            assert.strictEqual(obj.bool,true);
            assert.doesNotThrow(function(){
                obj.bool = '1';
            })
            assert.strictEqual(obj.bool,true);
        })
    })
})