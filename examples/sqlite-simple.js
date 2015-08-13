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

db.syncSchema({force:true},function(err){
    if(err) throw err;
    console.log('schema synced')

    var context = db.createContext();

    var user1 = context.create('User',{username:'user1'});
    var user2 = context.create('User',{username:'user2'});

    var company1 = context.create('Company',{name:'test company'});

    company1.addUsers([user1]);
    user2.setCompany(company1);

    context.save(function(err){
        if(err) throw err;
        context.destroy();
        console.log('completed and destroyed');
    })
})