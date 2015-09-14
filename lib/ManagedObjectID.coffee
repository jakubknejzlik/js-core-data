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
    return parseInt(ID.replace(/^[pt]/,''))



module.exports = ManagedObjectID