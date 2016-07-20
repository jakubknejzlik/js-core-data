# Express middleware

Middleware takes care about creating, destroying and assigning context to req.context. Context is destroyed on res `finish` event. 

```
var CoreData = require('js-core-data');
var express = require('express');

var database = new CoreData('sqlite://:memory:');
var app = new express();

// creates context and assigns it to req.context; context is automatically destroyed when response is finished
app.use(database.middleware());

app.get('/users',function(req,res,next){
    req.context.getObjects('User').then(function(users){
        res.send(users);
    }).catch(next)
})

app.listen(process.env.PORT || 5000)
```

## Next

Continue to [Examples](examples.md)