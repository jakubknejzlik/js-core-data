# js-core-data

CoreData is very powerful framework created by Apple for working with data. This module is heavily inspired by it's principles and simplifies usage by helper methods. Providing easy interface for defining data model, working with entities and persisting data to persistent store (MySQL and SQLite are currently supported).

# Context

When you create/update/access/delete data you always use context. Every time you create or fetch some object (entity instance) it's stored in context. Every updated attribute or relationship is stored in memory. After everything is ready, you just save the context.

The *best* thing about the context is that all changes are stored in memory until you save them into persistent store in ***one transaction***.


# Example

```
var CoreData = require('js-core-data');

var db = new CoreData('sqlite://:memory:');

var User = db.define('User',{username:'string'});
var Company = db.define('Company',{name:'string'});

db.defineRelationship(User,Company,'company',{inverse:'users'});
db.defineRelationship(Company,User,'users',{inverse:'company',toMany:true});

db.syncSchema({force:true},function(err){
    if(err) throw err;
    console.log('schema synced')

    var context = db.createContext();

    var user1 = context.create('User',{username:'user1'});
    var user2 = context.create('User',{username:'user2'});

    var company = context.create('Company',{name:'test company'});

    user1.setCompany(company);
    company.addUser(user2);

    context.save(function(err){
        if(err) throw err;
        context.destroy();
    })
})
```

## Fetching objects
```
...
var User = db.define('User',{username:'string'});
var Company = db.define('Company',{name:'string'});

db.defineRelationship(User,Company,'company',{inverse:'users'});
db.defineRelationship(Company,User,'users',{inverse:'company',toMany:true});

var context = db.createContext();
context.getObjects('User',{
		where:['SELF.company.name = %s','test company'],
		sort:'username'
	},function(err,users){
})

```

## Express middleware
```
var CoreData = require('js-core-data');
var express = require('express');

var db = new CoreData('sqlite://:memory:');
var app = new express();

// creates context and assigns it to req.context; context is automatically destroyed when response is finished
app.use(db.middleware());

app.get('/users',function(req,res,next){
    req.context.getObjects('User',function(err,users){
        if(err)return next(err);
        res.send(users);
    })
})

app.listen(process.env.PORT)

```

For more examples see */examples*

# TO-DO
- more detailed documentation (object subclasses etc.)
- foreign keys support
- more examples
- browser storage support
- more and more tests :)