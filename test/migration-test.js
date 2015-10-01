var assert = require('assert');
var tmp = require('tmp')

var CoreData = require('../index');

STORE_URL = 'sqlite://' + tmp.tmpNameSync();
//STORE_URL = 'mysql://root@localhost/test'

describe.only('migrations',function(){

    var db = new CoreData(STORE_URL)

    before(function(){
        model1 = db.createModel('0.1');
        model1.defineEntity('User',{
            firstname:'string',
            lastname:'string',
            testName:'string'
        });
        model1.defineEntity('Company',{
            name:'string'
        });
        model1.defineRelationshipManyToOne('User','Company','users','company')
        model1.defineRelationshipManyToMany('User','User','friends','friends')

        model2 = db.createModel('0.2');
        model2.defineEntity('User',{
            firstname:'string',
            lastname:'string',
            password:'string'
        });
        model2.defineEntity('Company',{
            name:'string'
        });
        model2.defineRelationshipManyToOne('User','Company','users2','company2')
        model2.defineRelationshipManyToMany('User','User','friends2','friends2')
        model2.defineRelationshipManyToMany('User','User','moreFriends','moreFriends')
        model2.defineRelationshipOneToMany('Company','User','users2','company2')

        migration1to2 = model2.createMigrationFrom(model1);
        migration1to2.addAttribute('User','password');
        migration1to2.renameRelationship('User','friends','friends2');
        migration1to2.addRelationship('User','moreFriends');
        migration1to2.addRelationship('User','company2');

    })

    it('should sync schema to 0.1',function(done){
        db.setModelVersion('0.1');
        db.syncSchema({ignoreVersion:true},done);
    })

    it('should sync schema from 0.1 to 0.2',function(done){
        db.setModelVersion('0.2');
        db.syncSchema(done);
    })
})