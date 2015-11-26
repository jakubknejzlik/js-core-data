var assert = require('assert');
var tmp = require('tmp');

var CoreData = require('../index');

var store_url = require('./get_storage_url').replace(':memory:',tmp.tmpNameSync());

describe('migrations',function(){

    var db = new CoreData(store_url,{logging:true});

    var company2Name = 'Company2' + Math.random()*10000

    before(function(){
        model1 = db.createModel('0.1');
        model1.defineEntity('User',{
            name:'string',
            test:'string',
            password:'string'
        });
        model1.defineEntity('Company',{
            name:'string'
        });
        model1.defineRelationshipManyToOne('User','Company','company','users');
        model1.defineRelationshipManyToMany('User','User','friends','friends');

        model2 = db.createModel('0.2');
        model2.defineEntity('User',{
            firstname:'string',
            lastname:'string',
            testNew:'string',
            addedColumn:'string'
        });
        model2.defineEntity(company2Name,{
            name:'string'
        });
        model2.defineRelationshipManyToOne('User',company2Name,'company2','users2');
//        model2.defineRelationshipOneToMany('Company','User','users','company')
        model2.defineRelationshipManyToMany('User','User','friends2','friends2');
        model2.defineRelationshipManyToMany('User','User','moreFriends','moreFriends');

        migration1to2 = model2.createMigrationFrom(model1);

        migration1to2.renameEntity('Company',company2Name)

        migration1to2.addAttribute('User','lastname');
        migration1to2.removeAttribute('User','password');
        migration1to2.renameAttribute('User','name','firstname');
        migration1to2.renameAttribute('User','test','testNew');

        migration1to2.renameRelationship('User','friends','friends2');
        migration1to2.addRelationship('User','moreFriends');
        migration1to2.removeRelationship('User','company');

        migration1to2.addScriptAfter(function(context,done){
            context.getObjects('User').then(function(users){
                users.forEach(function(user){
                    if(user.firstname){
                        var nameParts = user.firstname.split(' ');
                        user.firstname = nameParts[0];
                        user.lastname = nameParts[1];
                    }
                });
                done();
            }).catch(done);
        })

    });

    it('should sync schema to 0.1',function(done){
        db.setModelVersion('0.1');
        db.syncSchema({force:true},done);
    });

    it('should create user object in 0.1',function(done){
        var context = db.createContext();

        context.create('User',{name:'John Doe'});
        context.saveAndDestroy(done);
    });

    it('should sync schema from 0.1 to 0.2',function(done){
        db.setModelVersion('0.2');
        db.syncSchema(done);
    });


    it('should validate created user object in 0.2',function(done){
        var context = db.createContext();

        context.getObjects('User').then(function(users){
            assert.equal(users.length,1);
            var user = users[0];
            assert.equal(user.firstname,'John');
            assert.equal(user.lastname,'Doe');
            done();
        }).catch(done)
    })
});