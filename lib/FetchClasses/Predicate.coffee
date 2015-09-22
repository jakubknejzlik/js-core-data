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
      format = @format.replace(/[\s]*=[\s]*%@/g,'_id = %d').replace(/%s/g,'\'%s\'').replace(/%a/g,'%s')

      args = [format]
      for variable in @variables
        if variable is undefined or variable is null
          variable = null
        else if util.isArray(variable)
          variable = JSON.stringify(variable).replace(/\[/g,'(').replace(/\]/g,')')
        else if variable instanceof Date
          variable = moment(variable).format(DATE_FORMAT)
        else if variable instanceof ManagedObject
          variable = variable.objectID.recordId()
        else if variable instanceof ManagedObjectID
          variable = variable.recordId()
        else if variable._isAMomentObject
          variable = variable.format(DATE_FORMAT)
        args.push(variable)

      return util.format.apply(util.format,args);

module.exports = Predicate