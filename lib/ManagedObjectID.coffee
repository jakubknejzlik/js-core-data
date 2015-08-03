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
    components[components.length - 1].replace(/^[pt]/,'')



module.exports = ManagedObjectID