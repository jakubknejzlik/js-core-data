PersistentStoreRequest = require('./stores/PersistentStoreRequest')

class FetchRequest extends PersistentStoreRequest
  constructor: (@entity,@predicate,@sortDescriptors = [])->
    super 'fetch'
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