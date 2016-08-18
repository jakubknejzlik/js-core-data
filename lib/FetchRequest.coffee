assert = require('assert')
PersistentStoreRequest = require('./stores/PersistentStoreRequest')
EntityDescription = require('./Descriptors/EntityDescription')

class FetchRequest extends PersistentStoreRequest
  constructor: (@entity,@predicate,@sortDescriptors = [])->
    super 'fetch'
    assert(@entity instanceof EntityDescription,'entity must be instance of EntityDescription')
    @limit = 0
    @offset = 0
    @resultType = FetchRequest.RESULT_TYPE.MANAGED_OBJECTS
    @fields = null
    @havingPredicate = null
    @groupBy = null

  setLimit: (value)->
    @limit = value;
    @
  getLimit: ->
    @limit

  setOffset: (value)->
    @offset = value;
    @
  getOffset: ->
    @offset

  @RESULT_TYPE = {
    MANAGED_OBJECTS:1,
    VALUES:2
  }



module.exports = FetchRequest