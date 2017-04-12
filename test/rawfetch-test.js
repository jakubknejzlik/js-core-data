var assert = require('assert');

var CoreData = require('../index');

var store_url = require('./get_storage_url');

describe('raw fetch',function(){

    var db = new CoreData(store_url,{logging:false});

    before(function(done){
        var User = db.defineEntity('User',{
            firstname:'string',
            lastname:'string',
            lastnameTest:'string',
            value12345:'string',
            transientAttr:{
                type:'string',
                transient: true
            }
        });
        var Company = db.defineEntity('Company',{
            name:'string'
        });

        db.defineRelationshipManyToOne(User,Company,'company','users');
//        db.defineRelationshipOneToMany(Company,User,'users','company');
        db.defineRelationshipManyToMany(User,User,'friends','friends');

        db.syncSchema({force:true}).then(function(){
            var context = db.createContext();
            var user1 = context.create('User',{firstname:'John',lastname:'Doe'});
            var user2 = context.create('User',{firstname:'John2',lastname:'Doe2'});
            var user3 = context.create('User',{firstname:'John2',lastname:'Doe2'});
            var company = context.create('Company',{name:'John\'s company'});
            company.addUsers([user1,user2]);
            user1.addFriend(user2);
            user3.addFriends([user1,user2]);
            return context.save().then(function(){
                context.destroy();
                done();
            });
        }).catch(done)
    });

    it('fetch entity with fields',function(done){
        context = db.createContext();
        context.fetch('User',{
            where:{
                $or:{
                    'SELF.company._id>':0,
                    'SELF.company._id':null
                },
                '(50.01 - 20.33)>':25
            },
            having:{
                'companyName':'John\'s company'
            },
            fields:{
                companyName:'MIN(SELF.company.name)',
                firstname:'SELF.firstname',
                lastname:'SELF.lastname',
                name:'SELF.firstname'
            },
            group:'SELF.company.name,SELF.firstname,SELF.lastname,SELF._id',
            order:'SELF.firstname'
        }).then(function(data){
            assert.equal(data.length,2);
            assert.equal(data[0].firstname,'John');
            assert.equal(data[0].lastname,'Doe');
            assert.equal(data[0].name,'John');
            assert.equal(data[0].companyName,'John\'s company');
            assert.equal(data[1].firstname,'John2');
            context.destroy();
            done();
        }).catch(done);
    })
    it('fetch entity',function(done){
        context = db.createContext();
        context.fetch('User',{
            where:{
                $or:{
                    'SELF.company._id>':0,
                    'SELF.company._id':null
                },
                'SELF.firstname>':'.'
            },
            order:'SELF.firstname'
        }).then(function(data){
            assert.equal(data.length,3);
            assert.equal(data[0].firstname,'John');
            assert.equal(data[0].lastname,'Doe');
            assert.equal(data[1].firstname,'John2');
            context.destroy();
            done();
        }).catch(done);
    })
    it('fetch entity ordered',function(done){
        context = db.createContext();
        context.fetch('User',{
            fields:{
                0:'SELF.*',
                name:'SELF.firstname',
                'companyName':'SELF.company.name'
            },
            where:{
                'companyName':'John\'s company'
            },
            order:'companyName'
        }).then(function(data){
            assert.equal(data.length,2)
            context.destroy();
            done();
        }).catch(done);
    })
    it('fetch entity count',function(done){
        context = db.createContext();
        context.getObjectsCount('User',{
            fields:{
                0:'SELF.*',
                name:'SELF.firstname',
                'companyName':'SELF.company.name'
            },
            where:{
                $or:{'SELF._id':123}
            }
        }).then(function(data){
            console.log(data)
            //assert.equal(data.length,2)
            context.destroy();
            done();
        }).catch(done);
    })
});
