## Fetching objects
```
...
var User = db.define('User',{username:'string'});
var Company = db.define('Company',{name:'string'});

db.defineRelationship(User,Company,'company',{inverse:'users'});
db.defineRelationship(Company,User,'users',{inverse:'company',toMany:true});

var context = db.createContext();
context.getObjects('User',{
    where:['SELF.company.name = %s','test company'],
    sort:'username'
}).then(function(users){
    console.log(users);
    context.destroy();
})

```

## Counting objects

When you need to count how many object of specific (with firstname John) entity you have, you can use this method.

```
context.getObjectsCount('Car',{where:['SELF.firstname = %s','John']}).then(function(count){
    console.log(count)
});
```

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