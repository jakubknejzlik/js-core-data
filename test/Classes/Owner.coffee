ManagedObject = require('./../../lib/ManagedObject')

class Owner extends ManagedObject
  getFullName:()->
    return @name + ' ' + @lastName


module.exports = Owner