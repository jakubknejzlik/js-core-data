# js-core-data


[![Build Status](https://travis-ci.org/jakubknejzlik/js-core-data.svg?branch=master)](https://travis-ci.org/jakubknejzlik/js-core-data)
[![NPM Version][npm-image]][npm-url]
[![NPM Downloads][downloads-image]][downloads-url]

[![dependencies][dependencies-image]][dependencies-url]
[![devdependencies][devdependencies-image]][devdependencies-url]

[npm-image]: https://img.shields.io/npm/v/js-core-data.svg
[npm-url]: https://npmjs.org/package/js-core-data
[downloads-image]: https://img.shields.io/npm/dm/js-core-data.svg
[downloads-url]: https://npmjs.org/package/js-core-data

[dependencies-image]:https://david-dm.org/jakubknejzlik/js-core-data.png
[dependencies-url]:https://david-dm.org/jakubknejzlik/js-core-data
[devdependencies-image]:https://david-dm.org/jakubknejzlik/js-core-data/dev-status.png
[devdependencies-url]:https://david-dm.org/jakubknejzlik/js-core-data#info=devDependencies

==============

CoreData is very powerful framework created by Apple for working with data. This module is heavily inspired by it's principles and simplifies usage by implementing methods to fit server environment. Providing easy interface for defining data model, version migration, working with entities and persisting data to persistent store.

Currently supported persistent stores: MySQL, PostgreSQL, SQLite


# Important

This module is now used in few medium scale projects heading to production in few weeks. There are still some tasks to improve performance and abilities of data fetching. If you are using this module and consider it useful, any feedback or help is very appreciated.


# Example

```
var CoreData = require('js-core-data');

var db = new CoreData('sqlite://:memory:');

var User = db.define('User',{username:'string'});
var Company = db.define('Company',{name:'string'});

db.defineRelationship(User,Company,'company',{inverse:'users'});
db.defineRelationship(Company,User,'users',{inverse:'company',toMany:true});

db.syncSchema({force:true}).then(function(){
    console.log('schema synced')

    var context = db.createContext();

    var user1 = context.create('User',{username:'user1'});
    var user2 = context.create('User',{username:'user2'});

    var company = context.create('Company',{name:'test company'});

    user1.setCompany(company);
    company.addUser(user2);

    context.save().then(function(){
        context.destroy();
    })
})
```

For more examples see */examples*, especially TODO list REST backend example.


# Context

When you create/update/access/delete data you always use context. Every time you create or fetch some object (entity instance) it's stored in context. Every updated attribute or relationship is stored in memory. After everything is ready, you just save the context.

The *best* thing about the context is that all changes are stored in memory until you save them into persistent store in ***one transaction***.


# Working with objects

Objects are created in contexts. Every object exists in one instance per context (every time you fetch object twice, it's still the same instance).

```
var db = new CoreData(...);
var context = db.createContext();
var userId = 123;
context.getObjectWithId('User',userid).then(function(user1){
    context.getObjectWithId('User',userid).then(function(user2){
        console.log(user1 === user2); // true
    })
})
```

Every change to objects are made in memory (attributes and relationships). All changes are stored in persistent store (database) after save in one transaction.



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
}).then(function(users){
    console.log(users);
    context.destroy();
})

```

### Where (Predicate)

Where cindition is array with format `['format',arg1,arg2,arg3]` supports joins so you can query:

`['SELF.accessTokens.token = %s',req.params.token] // find user(s) with access token`

`['SELF.company.name = %s','test'] // find user(s) in company named 'test'`

## Relationships

There are two types of relationships toMany and toOne. Every relationship should have it's inverse (only in few cases it's possible do ignore inverse relationship).

Methods for accessing relationships are automaticaly defined for model.


```
...
db.define('User',{username:'string'});
db.define('Company',{name:'string'});

db.defineRelationshipManyToOne('User','Company','company','users');

var context = db.createContext();
var user = context.create('User');
var company = context.create('Company');

// generated methods
user.setCompany(company);
company.addUser(user);
company.addUsers([user,...]);
company.removeUser(user);
company.removeUsers([user,...]);

```

*Note: using SQL functions in predicate is store dependent (different set of functions for each store)*

## Raw fetch

You can fetch raw data from entities.

```
context.fetch('User',{
        fields:{
            companyName:'SELF.company.name',
            firstname:'SELF.firstname',
            lastname:'SELF.lastname',
            name:'SELF.firstname'
        },
        order:'SELF.firstname'
    })
    .then(function(data){
        console.log(data) // [{companyName:'...',firstname:'...',lastname:'...',name:'...'}]
    })

```

*Note: using SQL functions in raw fetch is store dependent (different set of functions for each store)*

## Counting objects

When you need to count how many object of specific (with firstname John) entity you have, you can use this method.

```
context.getObjectsCount('Car',{where:['SELF.firstname = %s','John']}).then(function(count){
    console.log(count)
});
```


# Schema synchronization and migration

You can specify multiple model schemas each with specific version. You can also specify schema migration from and to specific model version.

When you don't need model versioning, the `default` version is used.

To sync model schema use `syncSchema` method.

```
var CoreData = require('js-core-data');
var express = require('express');

var db = new CoreData(DATABASE_URL);

db.defineEntity('MyEntity',{attribute1:'string',attribute2:'string'});

db.syncSchema({force:true}).then(function(){ // force option drops existing tables
    console.log('schema synced');
});

```

For migrations and multiple version model use `createModel`, `createMigrationFrom` and `setVersionModel methods`

```
...
model1 = db.createModel('0.1');
model1.defineEntity('User',{username:{type:'string',unique:true}})

model2 = db.createModel('0.2');
model2.defineEntity('User',{username:{type:'string',unique:true},password:'string'})

migration1to2 = model2.createMigrationFrom(model1);
migration1to2.addAttribute('User','password');

// build schema for version 0.1
db.setModelVersion('0.1');
db.syncSchema().then(function(){
    // migrate schema to version 0.2
    db.setModelVersion('0.2');
    db.syncSchema().then(function(){
        // now model version is 0.2
    })
});
```

Every persistent store (data) has schema version stored in table `_meta`, during syncSchema every store checks it's model version, finds migrations needed to be performed and executes them. This way you don't need to take care about model version of each store.

Migrations can add/remove/rename attributes/relationships/entities.

*Note: currently store cannot join migrations (eg. 0.1=>0.2=>...=>0.8=>0.9)*

# Express middleware

Middleware takes care about creatint, destroying and assigning context to req.context. Context is destroyed on res.once('finish')

```
var CoreData = require('js-core-data');
var express = require('express');

var db = new CoreData('sqlite://:memory:');
var app = new express();

// creates context and assigns it to req.context; context is automatically destroyed when response is finished
app.use(db.middleware());

app.get('/users',function(req,res,next){
    req.context.getObjects('User').then(function(users){
        res.send(users);
    }).catch(next)
})

app.listen(process.env.PORT)

```



# TO-DO
- more detailed documentation (object subclasses, transient/private attributes etc.)
- more examples
- multiple migrations in one transaction
- sofisticated (store parsed) predicate
- caching mechanism (redis)