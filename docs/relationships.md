## Relationships

There are two types of relationships toMany and toOne. Every relationship should have it's inverse (only in few cases it's possible do ignore inverse relationship).

Methods for accessing relationships are automaticaly defined for model.


```
...
db.define('User',{username:'string'});
db.define('Company',{name:'string'});

db.defineRelationshipManyToOne('User','Company','company','users');

var context = db.createContext();
var user = context.create('User');
var company = context.create('Company');

// generated methods
user.setCompany(company);
company.addUser(user);
company.addUsers([user,...]);
company.removeUser(user);
company.removeUsers([user,...]);

```