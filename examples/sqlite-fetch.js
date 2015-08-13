var CoreData = require('../index');

var db = new CoreData('sqlite://:memory:');

User = db.defineEntity('User',{
    username:{
        type:'string',
        unique:true
    },
    firstname:'string',
    lastname:'string'
});

Company = db.defineEntity('Company',{
    name:'string'
});

db.defineRelationship(User,Company,'company',{inverse:'users'});
db.defineRelationship(Company,User,'users',{inverse:'company',toMany:true});

var context = db.createContext();

context.storeCoordinator.persistentStores[0].debug = true;

db.syncSchema({force:true},function(err){
    if(err) throw err;
    console.log('schema synced')

    var user1 = context.create('User',{username:'user1'});
    var user2 = context.create('User',{username:'user2'});

    var company1 = context.create('Company',{name:'test company'});

    company1.addUsers([user1]);
    user2.setCompany(company1);

    context.save(function(err){
        if(err) throw err;

        context.getObjects('User',{where:['SELF.company.name = %s','test company'],sort:'username'},function(err,users){
            if(err)throw err;
            console.log('found',users.length,'users:',users[0].username,'and',users[1].username);
        });
    })
})