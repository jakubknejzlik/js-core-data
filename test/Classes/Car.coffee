ManagedObject = require('./../../lib/ManagedObject')

class Car extends ManagedObject
  constructor:->
    super

  setBrandCustom:(value)->
    @brand = value+value

  getOwnerCustom:(callback)->
    @getOwner(callback)


module.exports = Car