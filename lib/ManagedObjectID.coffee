class ManagedObjectID extends Object
  constructor: (@stringValue,@entity)->
    @stringValue = @stringValue + ''
    @isTemporaryID = no

  isEqual: (objectID)->
    return @toString() == objectID.toString();

  toString: ()->
    @stringValue

  recordId: ()->
    components = @stringValue.split('/')
    ID = components[components.length - 1]
    if ID[0] is 'p'
      return parseInt(ID.substring(1).replace(/^[pt]/,''))
    else
      return ID



module.exports = ManagedObjectID