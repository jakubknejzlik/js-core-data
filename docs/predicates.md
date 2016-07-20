## Predicates

Where condition is array with format `['format',arg1,arg2,arg3]` supports joins so you can query:

`['SELF.accessTokens.token = %s',req.params.token] // find user(s) with access token`

`['SELF.company.name = %s','test'] // find user(s) in company named 'test'`

You can also use object notation:

`{'SELF.accessTokens.token':req.params.token}`

`{'SELF.company.name':'test'}`


*Note: using SQL functions in predicate is store dependent (different set of functions for each store)*

### Joins

When using predicate, you can create conditions for attributes of entities joined through relationships. For example:
 
```
var Person = database.defineEntity('Person',...);
var Company = database.defineEntity('Company',...);

database.defineRelationshipsOneToMany(Company, Person, 'employees', 'company');

var context = database.createContext();

context.getObjects('Person',{
    where: {'SELF.company.name': 'test company'}
}).then(function(persons){
    // all persons from company with name 'test company' 
})
```


### Object notation

Object notation support these format

- `{$and: []}` - joins array with `AND` 
- `{$or: []}` - joins array with `AND`
- `{'SELF.name': 'test'}` - transforms to `SELF.name = 'test'`
- `{'SELF.name!': 'test'}` - transforms to `SELF.name != 'test'`
- `{'SELF.name': ['test','test2']}` - transforms to `SELF.name IN ('test','test2')`
- `{'SELF.name!': ['test','test2']}` - transforms to `SELF.name NOT IN ('test','test2')`
- `{'SELF.age': 25}` - transforms to `SELF.age = 25`
- `{'SELF.age>': 25}` - transforms to `SELF.age > 25`
- `{'SELF.age<': 25}` - transforms to `SELF.age < 25`
- `{'SELF.age<=': 25}` - transforms to `SELF.age <= 25`
- `{'SELF.age>=': 25}` - transforms to `SELF.age >= 25`
- `{'SELF.name?': '*test?'}` - transforms to `SELF.name LIKE '%test_'` (`*` => `%` and `?` => `_`)
- `{'SELF.name': null}` - transforms to `SELF.name IS NULL`
- `{'SELF.name!': null}` - transforms to `SELF.name IS NOT NULL`


## Next

Continue to [Migrations](migrations.md)