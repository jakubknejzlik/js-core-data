assert = require('assert')
PersistentStoreRequest = require('./stores/PersistentStoreRequest')
EntityDescription = require('./Descriptors/EntityDescription')

class FetchRequest extends PersistentStoreRequest
  constructor: (@entity,@predicate,@sortDescriptors = [])->
    super 'fetch'
    assert(@entity instanceof EntityDescription,'entity must be instance of EntityDescription')
    @limit = 0
    @offset = 0

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



module.exports = FetchRequest;