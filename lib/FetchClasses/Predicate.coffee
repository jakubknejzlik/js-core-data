util = require('util')
ManagedObjectID = require('./../ManagedObjectID')
moment = require('moment')

DATE_FORMAT = 'YYYY-MM-DD HH:mm:ss'

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
        if variable instanceof Date
          variable = moment(variable).format(DATE_FORMAT)
        else if variable._isAMomentObject
          variable = variable.format(DATE_FORMAT)
        args.push(variable)
      util.format.apply(util.format,args);

module.exports = Predicate