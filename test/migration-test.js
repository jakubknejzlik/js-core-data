var assert = require('assert');
var tmp = require('tmp');
var fs = require('fs');
var async = require('async');


var CoreData = require('../index');

storeTmpName = tmp.tmpNameSync();
var store_url = require('./get_storage_url').replace(':memory:',storeTmpName);

describe('migrations',function(){

    var db = new CoreData(store_url,{logging:false});

    var company2Name = 'Company2' + Math.round(Math.random()*10000);
    var userFriendsRelationshipName = 'friends' + Math.round(Math.random()*10000);

    before(function(){
        var model1 = db.createModel('0.1');
        model1.defineEntity('User',{
            name:'string',
            test:'string',
            password:'string'
        });
        model1.defineEntity('Company',{
            name:'string'
        });
        model1.defineEntity('Test',{
            name: 'string'
        })
        model1.defineRelationshipManyToOne('User','Company','company','users',{onDelete:'cascade'});
        model1.defineRelationshipManyToOne('User','Company','invalidCompany','invalidUsers',{onDelete:'cascade'});
        model1.defineRelationshipManyToMany('User','User','friends','friends');

        var model2 = db.createModel('0.2');
        model2.defineEntity('User',{
            firstname:'string',
            lastname:'string',
            testNew:'string',
            addedColumn:'string'
        });
        model2.defineEntity(company2Name,{
            name123:'string',
            name2:'string'
        });
        model2.defineEntity('Test2',{
            name:'string'
        });
        model2.defineRelationshipManyToOne('User',company2Name,'company2','users2',{onDelete:'cascade'});
        model2.defineRelationshipOneToMany('User',company2Name,'favoriteCompanies','favoritedUser',{onDelete:'cascade'});
//        model2.defineRelationshipOneToMany('Company','User','users','company')
        model2.defineRelationshipManyToMany('User','User',userFriendsRelationshipName,userFriendsRelationshipName);
        model2.defineRelationshipManyToMany('User','User','moreFriends','moreFriends');

        var migration1to2 = model2.createMigrationFrom(model1);

        migration1to2.removeEntity('Test')
        migration1to2.addEntity('Test2')
        migration1to2.renameEntity('Company',company2Name);
        migration1to2.addAttribute(company2Name,'name2');
        migration1to2.renameAttribute(company2Name,'name','name123');

        migration1to2.addAttribute('User','lastname');
        migration1to2.addAttribute('User','addedColumn');
        migration1to2.removeAttribute('User','password');
        migration1to2.renameAttribute('User','name','firstname');
        migration1to2.renameAttribute('User','test','testNew');

        migration1to2.renameRelationship('User','company','company2');

        migration1to2.renameRelationship('User','friends',userFriendsRelationshipName);
        migration1to2.addRelationship('User','moreFriends');
        migration1to2.addRelationship('User','favoriteCompanies');
        migration1to2.removeRelationship('User','invalidCompany');
        //migration1to2.removeRelationship('User','company');

        migration1to2.addScriptAfter(function(context,done){
            context.getObjects('User').then(function(users){
                context.getObjects(company2Name).then(function(companies) {
                    users.forEach(function (user) {
                        if (user.firstname) {
                            var nameParts = user.firstname.split(' ');
                            user.firstname = nameParts[0];
                            user.lastname = nameParts[1];
                        }
                    });
                    companies.forEach(function(company){
                        company.name2 = company.name123 + '2';
                    });
                    done();
                })
            }).catch(done);
        });

        var model3 = db.createModel('0.3');
        model3.defineEntity('User',{
            firstname:'string',
            lastname:'string',
            testNew:'string',
            addedColumn:'string'
        });
        model3.defineEntity(company2Name,{
            name123:'string',
            name2:'string'
        });
//        model2.defineRelationshipManyToOne('User',company2Name,'company2','users2');
////        model2.defineRelationshipOneToMany('Company','User','users','company')
//        model2.defineRelationshipManyToMany('User','User',userFriendsRelationshipName,userFriendsRelationshipName);
//        model2.defineRelationshipManyToMany('User','User','moreFriends','moreFriends');
        var migration2to3 = model3.createMigrationFrom(model2);
        migration2to3.removeRelationship('User','company2')
        migration2to3.removeRelationship('User',userFriendsRelationshipName)
        migration2to3.removeRelationship('User','moreFriends')

        var model4 = db.createModel('0.4');
        model4.createMigrationFrom(model3);
        var model5 = db.createModel('0.5');
        model5.createMigrationFrom(model4);
        var model6 = db.createModel('0.6');
        model6.createMigrationFrom(model5);
        var model7 = db.createModel('0.7');
        model7.createMigrationFrom(model6);


        var modelFail = db.createModel('fail');
        var migrationFail = modelFail.createMigrationFrom(model3);

        migrationFail.addScriptBefore(function(context,done){
            context.getObjects('blahnonexisting').then(function(){
                done()
            }).catch(done);
        },'my failing script')
    });
    after(function(){
        return db.closeAllConnections().then(function() {
            if(fs.existsSync(storeTmpName))fs.unlinkSync(storeTmpName)
        })
    });

    it('should sync schema to 0.1',function(done){
        db.setModelVersion('0.1');
        db.syncSchema({force:true},done);
    });

    it('should create user object in 0.1',function(done){
        var context = db.createContext();

        var user = context.create('User',{name:'John Doe'});
        var company = context.create('Company',{name:'John\'s company'});
        company.addUser(user);
        context.saveAndDestroy(done);
    });

    it('should sync schemas',function(done){
        var versions = ['0.2','0.3']
        async.forEachSeries(versions,function(version,cb){
            db.setModelVersion(version);
            db.syncSchema().then(cb).catch(function(err){
                err.message = 'cannot migrate to version ' + version + '; error: ' + err.message
                return cb(err)
            });
        },done)
    });


    it('should validate user objects created in 0.2',function(done){
        var context = db.createContext();
        console.log(db.modelVersion)
        context.getObjects('User').then(function(users){
            assert.equal(users.length,1);
            var user = users[0];
            assert.equal(user.firstname,'John');
            assert.equal(user.lastname,'Doe');
            done();
        }).catch(done)
    });

    it('should validate company objects created in 0.2',function(done){
        var context = db.createContext();

        context.getObjects(company2Name).then(function(companies){
            assert.equal(companies.length,1);
            var company = companies[0];
            assert.equal(company.name123,'John\'s company');
            assert.equal(company.name2,'John\'s company2');
            done();
        }).catch(done)
    });

    it('should fail to migrate to version fail',function(done){
        db.setModelVersion('fail');
        db.syncSchema(function(err){
            assert.ok(err);
            done();
        });
    })


    it('should migrate with force anytime',function(){
        db.setModelVersion('0.1')
        return db.syncSchema({force:true})
    })

    it('should migrate multiple versions',function(){
        db.setModelVersion('0.1')
        return db.syncSchema({force:true}).then(function(){
            db.setModelVersion('0.7')
            return db.syncSchema()
        })
    })
});
