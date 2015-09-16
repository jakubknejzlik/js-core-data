util = require('util')
ManagedObject = require('./../ManagedObject')
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
      format = @format.replace(/[\s]*=[\s]*%@/g,'_id = %d').replace(/%s/g,'\'%s\'')

      args = [format]
      for variable in @variables
        if variable instanceof Date
          variable = moment(variable).format(DATE_FORMAT)
        else if variable instanceof ManagedObject
          variable = variable.objectID.recordId()
        else if variable instanceof ManagedObjectID
          variable = variable.recordId()
        else if variable._isAMomentObject
          variable = variable.format(DATE_FORMAT)
        args.push(variable)
      util.format.apply(util.format,args);

module.exports = Predicate