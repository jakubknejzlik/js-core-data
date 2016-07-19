# Schema

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