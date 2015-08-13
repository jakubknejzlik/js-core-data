#js-core-data

CoreData is very powerful framework created by Apple for working with data. This module is heavily inspired by it's principles and simplifies usage by helper methods. Providing easy interface for defining data model, working with entities and persisting data to persistent store (MySQL and SQLite are currently supported).

#Context

When you create/update/access/delete data you always use context. Every time you create or fetch some object (entity instance) it's stored in context. Every updated attribute or relationship is stored in memory. After everything is ready, you just save the context.

The *best* thing about the context is that all changes are stored in memory until you save them into persistent store in ***one transaction***.


#Example

```
var CoreData = require('js-core-data');

var db = new CoreData('sqlite://:memory:');

Entity = db.defineEntity('Entity',{attribute1:'string'});
Entity2 = db.defineEntity('Entity2',{attribute1:'string'});

db.defineRelationship(Entity,Entity2,'myentity',{inverse:'myentity2'});
db.defineRelationship(Entity2,Entity,'myentity2',{inverse:'myentity',toMany:true});

db.syncSchema({force:true},function(err){
    if(err) throw err;
    console.log('schema synced')

    var context = db.createContext();

    var obj = context.create('Entity',{username:'user1'});
    var obj2 = context.create('Entity2',{name:'test company'});

    obj.setMyentity(obj2);
    //or obj.addMyentity2s([obj1]);

    context.save(function(err){
        if(err) throw err;
        context.destroy();
    })
})
```

##Fetching objects
```
...
var User = db.define('User',{username:'string});
var Company = db.define('Company',{name:'string});

db.defineRelationship(User,Company,'company',{inverse:'users'});
db.defineRelationship(Company,User,'users',{inverse:'company',toMany:true});

var context = db.createContext();
context.getObjects('User',{
		where:['SELF.company.name = %s','test company'],
		sort:'username'
	},function(err,users){
})

```

For more examples see */examples*

##TO-DO
- more detailed documentation (object subclasses etc.)
- foreign keys support
- more examples
- browser storage support
- promise support
- more and more tests :)