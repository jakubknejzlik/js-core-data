util = require('util')
ManagedObjectID = require('./../ManagedObjectID')

class Predicate extends Object
  constructor: (@format,@variables...)->

  isObjectIDPredicate:->
    return @format instanceof ManagedObjectID

  objectID:->
    @format

  toString:->
    if @format instanceof ManagedObjectID
      return '`_id` = ' + @format.recordId();
    else
      args = [@format.replace(/%s/g,'\'%s\'')]
      for variable in @variables
        args.push(variable)
      util.format.apply(util.format,args);

module.exports = Predicate