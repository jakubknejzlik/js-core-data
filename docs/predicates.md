## Predicates

Where condition is array with format `['format',arg1,arg2,arg3]` supports joins so you can query:

`['SELF.accessTokens.token = %s',req.params.token] // find user(s) with access token`

`['SELF.company.name = %s','test'] // find user(s) in company named 'test'`

You can also use object format:

`{'SELF.accessTokens.token':req.params.token}`

`{'SELF.company.name':'test'}`


*Note: using SQL functions in predicate is store dependent (different set of functions for each store)*