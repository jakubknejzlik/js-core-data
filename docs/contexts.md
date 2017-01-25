## Context

When you create/update/access/delete data you always use context. Every time you create or fetch some object (entity instance) it's stored in context. Every updated attribute or relationship is stored in memory. After everything is ready, you just save the context.

The *best* thing about the context is that all changes are stored in memory until you save them into persistent store in ***one transaction***.


## Creating contexts

You can create contexts with method `createContext()` on database client.

```
var context = database.createContext();
```

When you have context, you can create new entities in it. This code creates new Author entity. 

```
var author = context.create('Author',{firstname: 'John', lastname: 'Doe'});

// alternatively you can upsert object
// var data = {firstname: 'John', lastname: 'Doe'};
// context.getOrCreateObject('Author',{where:data},data).then(function(author) {
// });
```

You can also create relationships.

```
var book = context.create('Book',{title: 'Book written by John Doe'});
book.setAuthor(author);
// or author.addBook(book);
```

After you have created all objects. You can save context. By saving context all created/updated objects are stored in database in one transaction.

```
context.save().then(function(){
    console.log('all saved');
})
```

It's important to cleanup memory. This is done by destroying context. When context is destroyed, no more changes could be done with it.

```
context.destory();
// context.saveAndDestroy(); saves context and destroys it in one call
```


It's important to realise that created object are considered *temporary* until context is saved. Every temporary object has temporary id (id is updated automatically after save).

You can check object's state with these attributes:

- `object.isInserted` - true when object is inserted to context, but not saved already
- `object.isUpdated` - true when object has changes that are not saved to store
- `object.isDeleted` - true when object was deleted (if you still have reference to it)
- `object.isFault` - object is in fault state when it has not fetched data from database (fetch is done automatically)

## Next

Continue to [Schema](schema.md)