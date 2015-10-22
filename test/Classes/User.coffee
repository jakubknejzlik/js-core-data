ManagedObject = require('./../../lib/ManagedObject')

class User extends ManagedObject
  getFullName:()->
    return @firstname + ' ' + @lastname

  setFullName:(fullName)->
    parts = fullName.split(' ')
    @firstname = parts[0]
    @lastname = parts[1]


module.exports = User