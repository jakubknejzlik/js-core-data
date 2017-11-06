## Seeding

When you have default data (eg. default admin user, country list, etc.) for your application or for dev/staging version, you usually need to seed database.

Seeding can be run over whole folders by simply running `db.seed.run(path)`:


```
const CoreData = require('js-core-data')

const db = new CoreData(...)

db.seed.run("/path/to/seeding/folder")
```


Seeding folder contains json files named by entities. For example if you have following schema:

```
Person:
    columns:
        firstname: string
        lastname: string
    relationships:
        company:
            entity: Company
            inverse: employees

Company:
    columns:
        name: string
    relationships:
        employees:
            entity: Person
            toMany: true
            inverse: company
```

You should create following folder structure:

```
/path/to/seeding/folder
|
|- Person.json
|- Company.json
```

### Example data

```
// Person.json
[
    {"id":"1","firstname":"John","lastname":"Doe","company":1},
    {"id":"2","firstname":"Jane","lastname":"Doe"},
    {"id":"3","firstname":"Sara","lastname":"O'Connor"},
    {"id":"4","firstname":"Lara","lastname":"Croft"}
]
```

```
// Company.json
[
    {"id":"1","name":"Test company"},
    {"id":"2","name":"Test2 company","employees":[2,3,4]}
]
```

*NOTE: Ids are not required, but are useful when you want to create relationships between objects*

## Next

Continue to [Examples](examples.md)