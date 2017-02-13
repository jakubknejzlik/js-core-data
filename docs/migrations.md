## Migrations

For migrations and multiple version model use `createModel`, `createMigrationFrom`/`createMigrationTo` and `setVersionModel` methods

Migration is collection of steps that need to be performed to migrate between two versions. You can create migration between two versions:

```
var model1 = database.createModel('v1');
var model2 = database.createModel('v2');

var migration = model1.createMigrationTo(model2);
// or: var migration = model2.createMigrationFrom(model1);
```

You add steps to migration with these methods:

- `addEntity(entityName)`
- `remvoeEntity(entityName)`
- `addAttribute(entityName, attributeName)`
- `removeAttribute(entityName, attributeName)`
- `addRelationship(entityName, relationshipName)`
- `removeRelationship(entityName, relationshipName)`
- `addScriptBefore(function)` - add function that runs before migration start
- `addScriptAfter(function)` - add function that runs after migration start


Example:

```
model1 = database.createModel('0.1');
model1.defineEntity('User',{username:{type:'string',unique:true}})

model2 = database.createModel('0.2');
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

### Running migration

Migration is performed automaticaly with `syncSchema(options)` method:

- `options`
    - `ignoreMissingVersion` - when `true` sync doesn't fail if no current version is found in `_meta` table 
    - `force` - force recreate schema (drops all tables and creates them again)
    - `automigration` - see below for more information

Example:

```
database.syncSchema().then(function(){
    // tables synced
})
```

Every persistent store (database) has schema version stored in table `_meta`, during `syncSchema` every store checks it's model version, finds migrations needed to be performed and executes them. This way you don't need to take care about model version of each store.


*Note: stores can join multiple migrations (eg. 0.1=>0.2=>...=>0.8=>0.9), currently not performed in one transaction*

## Automatic migration

Since version 1.6.0 `js-core-data` can generate automigrations. It adds/removes missing entities/attributes/relationships. Automatic migration can be used only between two existing models (thus you have to use schema definitions and model version related to current database model version must exists).
  
Usage:
```
database.syncSchema({automigration: true}).then(function(){
    // tables synced
})
```

## Next

Continue to [Express middleware](express.md)