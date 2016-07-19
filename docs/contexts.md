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

