class PersistentStore
  constructor:(@persistentStoreCoordinator,@URL,@globals) ->

  getType: ->
    throw new Error('method must be overwritten')

  syncSchema: (options,callback)->
    throw new Error('method must be overwritten')

module.exports = PersistentStore;