ManagedObject = require('./../../lib/ManagedObject')

class Hello extends ManagedObject
  awakeFromInsert:()->
    super
    @awakeFromInsertValue = 'awaken'
  awakeFromFetch:()->
    super
    @awakeFromFetchValue = 'fetched'

  willSave:()->
    @saveValue = 'will save'
  didSave:()->
    @saveValue = 'did save'

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

  getFullName2:()->
    return @firstname + ' ' + @lastname

module.exports = Hello