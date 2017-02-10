Promise = require('bluebird')

CoreData = require('../CoreData')

CoreData::syncSchema = (options,callback)->
  if typeof options is 'function'
    callback = options
    options = undefined
  options = options or {}
  return Promise.each(@_persistentStoreCoordinator().persistentStores,(store) =>
    return @syncStoreSchema(store,options)
  ).thenReturn(null).asCallback(callback)


CoreData::syncStoreSchema = (store, options) ->
  objectModel = @model

  return store.getCurrentVersion().then((databaseModelVersion)=>
    if databaseModelVersion is objectModel.version and not options.force
      return
    else if not databaseModelVersion and not options.ignoreMissingVersion and not options.force
      throw new Error('current version not found, rerun syncSchema with enabled option ignoreMissingVersion')
    else if (not databaseModelVersion and options.ignoreMissingVersion) or options.force
      return store.syncSchema(options)
    else
      migrations = objectModel.getMigrationsFrom(databaseModelVersion)
      if not migrations or migrations.length is 0
        if options.automigration
          databaseModel = @getModel(databaseModelVersion)
          migrations = [objectModel.autogenerateMigrationFromModel(databaseModel, options)]
        else
          throw new Error('migration ' + databaseModelVersion + '=>' + objectModel.version + ' not found')
      return Promise.each(migrations,(migration) =>
        return store.runMigration(migration)
      )
  )