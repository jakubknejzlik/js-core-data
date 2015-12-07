ManagedObject = require('./../../lib/ManagedObject')

class Hello extends ManagedObject
  getFullName:()->
    return @firstname + ' ' + @lastname

  setFullName:(fullName)->
    if fullName is null
      @firstname = null
      @lastname = null
    else
      parts = fullName.split(' ')
      @firstname = parts[0]
      @lastname = parts[1]

module.exports = Hello