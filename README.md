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
# Installation

View Node Package Manager:

```npm install --save js-core-data```

Then install database client:

```npm install --save mysql|sqlite3|pg```


# Documentation

For more information please visit documentation: [ViewDocs.io documentation](http://jakubknejzlik.viewdocs.io/js-core-data/)

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

# Running tests

To run tests locally you need `docker` and `docker-compose` installed

* first start database services:

```
docker-compose up
```

* then run tests:

```
npm test
```
