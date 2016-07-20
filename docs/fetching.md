## Fetching objects

When you have your database ready. Fetching could be easily done with following methods:

* `context.getObjects(entityName, options)` - get list of objects for given entity name
* `context.getObject(entityName, options)` - get single object (similar to `getObjects`, but returns first object)
* `context.getObjectWithId(entityName, id)` - get object with specific `id` (every object has `id` attribute, see [Schema section](schema.md) for more information) 
* `context.getObjectWithObjectID(ObjectID)` - get object with specific `ObjectID` (`ObjectID` is unique resource identifier for every object, see [Schema section](schema.md) for more information)

For example fetching all books.

```
context.getObjects('Book').then(function(users){
    // array of users
})
```

#### Fetching options

- `limit` - limit number of returned objects (defualt: *Infinite*, for `getObject` is forces to *1*)
- `offset` - offset for results (used for pagination) 
- `where` - builds *WHERE* statement with predicate (see [Predicates section](predicates.md) for more information)
- `having` - builds *HAVING* statement with predicate (see [Predicates section](predicates.md) for more information)
- `order` - attributes to sort by (string or array of strings, for descending order use `-` sign: `-name`)


## Counting objects

When you need to count how many object of specific (with firstname John) entity you have, you can use this method.

* `context.getObjectsCount(entityName, options)`

```
context.getObjectsCount('Book').then(function(count){
    console.log('number of books:', count)
});
```

#### Counting options

- `where` - builds *WHERE* statement with predicate
- `having` - builds *HAVING* statement with predicate 


## Complex fetch example

```
context.getObjects('Author', {
    limit: 30,
    offset: 60,
    where: {firstname: 'John'},
    order: 'lastname'
}).then(function(authors){
    // array of authors with firstname equal to John, ordered by lastname, items 60-89
})
```

## Attribute names

You can prefix all attribute names with `SELF.`, which references table in current query. 

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

## Next

Continue to [Predicates](predicates.md)