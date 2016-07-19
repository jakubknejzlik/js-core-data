# Migrations

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