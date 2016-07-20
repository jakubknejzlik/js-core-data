## Installation

You can install `js-core-data` using NPM:

```
npm install js-core-data --save
```

## Database module

Database libraries are not installed as dependencies. You need to install module for database you are planning to use.

- For SQLite  
```
npm install sqlite3 --save
```

- For MySQL  
```
npm install mysql --save
```

- For Postgres  
```
npm install pg --save
```

## Create orm client

Create client with database url:

```
var CoreData = require('js-core-data');

var url = process.env.DATABASE_URL || 'sqlite://:memory:'; // :memory: identifies resource for sqlite in memory database

var database = new CoreData(url)
```


## Define model

js-core-data is ORM, so you need to define your entities. Easiest way is to creating directly on database client:

```
var database = ...;

var Book = database.createEntity('Book',{
    title: 'string',
    publishYear: 'int'
})

var Author = database.createEntity('Author',{
    firstname: 'string',
    lastname: 'string'
})

database.defineRelationshipOneToMany(Author, Book, 'books', 'author')
```

This is just simple example. For complete list of methods, attribute definition and versioning support see [Schema section](schema.md).
   
   
## Build table schema

When you have schema defined, you can sync database tables by running:

```
database.syncSchema().then(function(){
    console.log('done...')
})
```

## Insert data

Now you have everything set to start working with data. Everything is done in context, create one and insert/query entries.


```
var database = ...;

var context = database.createContext();

var book = context.create('Book',{title: 'The Da Vinci Code', publishYear: 2003})
var author = context.create('Author',{firstname: 'Dan', lastname: 'Brown'})

book.setAuthor(author)

context.saveAndDestroy().then(function(){
    console.log('all saved...now fetch')
})
```

## Fetch data

You can fetch data from database also with context.


```
context.getObjects('Book').then(function(books){
    // books variable contains array of Book entities
})
```

For more details visit [Fetching section](fetching.md).

## Next

Continue to [Contexts](contexts.md)