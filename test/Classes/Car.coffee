ManagedObject = require('./../../lib/ManagedObject')

class Car extends ManagedObject
  constructor:->
    super

  setBrand:(value)->
#    if typeof value is 'string'
#      value += 'x'
    @_setBrand(value)

  setBrandCustom:(value)->
    @brand = value+value

  getOwnerCustom:(callback)->
    @getOwner(callback)


module.exports = Car