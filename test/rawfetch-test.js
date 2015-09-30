var assert = require('assert');

var CoreData = require('../index');

//STORE_URL = 'sqlite://:memory:'
STORE_URL = 'mysql://root@localhost/test'

describe('raw fetch',function(){

    var db = new CoreData(STORE_URL,{logging:false})

    before(function(done){
        var User = db.defineEntity('User',{
            firstname:'string',
            lastname:'string'
        });
        var Company = db.defineEntity('Company',{
            name:'string'
        });

//        db.defineRelationshipManyToOne(User,Company,'users','company');
        db.defineRelationshipOneToMany(Company,User,'users','company');
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
    })

    it('fetch entity',function(done){
        context = db.createContext()
        context.fetch('User',{group:'SELF.firstname',fields:{companyName:'SELF.company.name',firstname:'SELF.firstname',lastname:'SELF.lastname',name:'CONCAT(SELF.firstname,\' \',SELF.lastname)'},order:'SELF.firstname'}).then(function(data){
            assert.equal(data.length,2);
            assert.equal(data[0].firstname,'John');
            assert.equal(data[0].lastname,'Doe');
            assert.equal(data[0].name,'John Doe');
            assert.equal(data[0].companyName,'John\'s company');
            assert.equal(data[1].firstname,'John2');
            context.destroy();
            done();
        }).catch(done);
    })
})