assert = require('assert')
PersistentStoreRequest = require('./stores/PersistentStoreRequest')
EntityDescription = require('./Descriptors/EntityDescription')

class FetchRequest extends PersistentStoreRequest
  constructor: (@entity,@predicate,@sortDescriptors = [])->
    super 'fetch'
    assert(@entity instanceof EntityDescription,'entity must be instance of EntityDescription')
    @_limit = 0
    @_offset = 0

  setLimit: (value)->
    @_limit = value;
    @
  getLimit: ->
    @_limit

  setOffset: (value)->
    @_offset = value;
    @
  getOffset: ->
    @_offset



module.exports = FetchRequest;