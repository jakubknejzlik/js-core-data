class PersistentStore
  constructor:(@persistentStoreCoordinator,@URL) ->

  @getType: ->
    throw new Error('method must be overwritten')

module.exports = PersistentStore;