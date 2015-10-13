var assert = require('assert');
var tmp = require('tmp')

var CoreData = require('../index');

var store_url = require('./get_storage_url').replace(':memory:',tmp.tmpNameSync());

describe.only('migrations',function(){

    var db = new CoreData(store_url)

    before(function(){
        model1 = db.createModel('0.1');
        model1.defineEntity('User',{
            firstname:'string',
            lastname:'string',
            test:'string'
        });
        model1.defineEntity('Company',{
            name:'string'
        });
        model1.defineRelationshipManyToOne('User','Company','company','users')
        model1.defineRelationshipManyToMany('User','User','friends','friends')

        model2 = db.createModel('0.2');
        model2.defineEntity('User',{
            firstname:'string',
            password:'string',
            testNew:'string',
            addedColumn:'string'
        });
        model2.defineEntity('Company',{
            name:'string'
        });
        model2.defineRelationshipManyToOne('User','Company','company2','users2')
//        model2.defineRelationshipOneToMany('Company','User','users','company')
        model2.defineRelationshipManyToMany('User','User','friends2','friends2')
        model2.defineRelationshipManyToMany('User','User','moreFriends','moreFriends')

        migration1to2 = model2.createMigrationFrom(model1);

        migration1to2.addAttribute('User','password');
        migration1to2.removeAttribute('User','lastname');
        migration1to2.renameAttribute('User','test','testNew');

        migration1to2.renameRelationship('User','friends','friends2');
        migration1to2.addRelationship('User','moreFriends');
        migration1to2.removeRelationship('User','company');

    })

    it('should sync schema to 0.1',function(done){
        db.setModelVersion('0.1');
        db.syncSchema({force:true},done);
    })

    it('should sync schema from 0.1 to 0.2',function(done){
        db.setModelVersion('0.2');
        db.syncSchema(done);
    })
})