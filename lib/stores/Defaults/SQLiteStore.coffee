GenericSQLStore = require('./GenericSQLStore')
PersistentStoreRequest = require('./../PersistentStoreRequest')
GenericPool = require('generic-pool')
async = require('async')
ManagedObjectID = require('./../../ManagedObjectID')
Predicate = require('./../../FetchClasses/Predicate')

SQLConnection = require('./SQLConnection')

try
  require('sqlite3')
catch e
  throw new Error('sqlite3 module is required to use SQLite storage, please install it by running npm install --save sqlite3')

sqlite = require('sqlite3')

_ = require('underscore');
_.mixin(require('underscore.inflections'));

privateTableNames = ['sqlite_sequence']

class SQLiteStore extends GenericSQLStore
  createConnection:(url)->
    return new SQLiteConnection(url,@)


  _insertQueryForManyToMany:(relationship,object,addedObject) ->
    return 'INSERT OR IGNORE INTO ' + @quoteSymbol + @_getMiddleTableNameForManyToManyRelation(relationship) + @quoteSymbol + ' (reflexive,' + @quoteSymbol + relationship.name + '_id' + @quoteSymbol + ') VALUES (' + @_recordIDForObjectID(object.objectID) + ',' + @_recordIDForObjectID(addedObject.objectID) + ')'


  createSchemaQueries: (options = {},transaction,callback)->
    sqls = []
    transaction.query('SELECT name as table_name FROM sqlite_master WHERE type=\'table\'',(err,rows)=>
      return callback(err) if err
      if options.force
        for row in rows
          if row['table_name'] not in privateTableNames
            sqls.push(@_dropTableQuery(row['table_name']))

      try
        objectModel = @storeCoordinator.objectModel

        for key,entity of objectModel.entities
          sqls = sqls.concat(@createEntityQueries(entity,options.force))
        for key,entity of objectModel.entities
          sqls = sqls.concat(@createEntityRelationshipQueries(entity,options.force))

        sqls.push('CREATE TABLE IF NOT EXISTS `_meta` (`key` varchar(10) NOT NULL,`value` varchar(250) NOT NULL,PRIMARY KEY (`key`))')
        sqls.push('INSERT OR IGNORE INTO `_meta` VALUES(\'version\',\'' + objectModel.version + '\')')

        callback(null,sqls)
      catch err
        callback(err)
    )

  createEntityQueries:(entity,force = no,options = {})->
    sqls = []
    tableName = @_formatTableName(entity.name)
    parts = ['`_id` INTEGER PRIMARY KEY AUTOINCREMENT']

    for attribute in entity.getNonTransientAttributes()
      columnDefinition = @_columnDefinitionForAttribute(attribute)
      if columnDefinition
        parts.push(columnDefinition);
      else
        throw new Error('unknown attribute type ' + attribute.type)

    if not options.noRelationships
      for relationship in entity.relationships
        if not relationship.toMany
          parts.push('`'+relationship.name+'_id` int(11) DEFAULT NULL REFERENCES `' + @_formatTableName(relationship.destinationEntity.name) + '`(`_id`) ON DELETE ' + relationship.getOnDeleteRule())

#    if force
#      sqls.push('DROP TABLE IF EXISTS `' + tableName + '`')
    sql = 'CREATE TABLE IF NOT EXISTS `' + tableName + '` ('
    sql += parts.join(',')
    sql += ')'

    for index in @_indexesForEntity(entity)
      sql +=";CREATE " + (if index.type is 'unique' then 'UNIQUE' else '') + " INDEX IF NOT EXISTS `"+index.name+'` ON `'+tableName+'` (`'+index.columns.join('`,`')+"`)"

    sqls.push(sql)

    if not options.ignoreRelationships
      sqls = sqls.concat(@createEntityRelationshipQueries(entity,force))

    return sqls

  createRelationshipQueries:(relationship,force)->
    sqls = []
    if relationship.toMany
      inversedRelationship = relationship.inverseRelationship()
      if inversedRelationship.toMany
        reflexiveRelationship = @_relationshipByPriority(relationship,inversedRelationship)
        reflexiveTableName = @_getMiddleTableNameForManyToManyRelation(reflexiveRelationship)
#        if force
#          sqls.push('DROP TABLE IF EXISTS `' + reflexiveTableName  + '`')
        parts = []
        parts.push('`'+reflexiveRelationship.name+'_id` int(11) NOT NULL REFERENCES `' + @_formatTableName(reflexiveRelationship.destinationEntity.name) + '`(`_id`) ON DELETE CASCADE')
        parts.push('`reflexive` int(11) NOT NULL REFERENCES `' + @_formatTableName(reflexiveRelationship.entity.name) + '`(`_id`) ON DELETE CASCADE')
        parts.push('PRIMARY KEY (`'+reflexiveRelationship.name+'_id`,`reflexive`)')
        sqls.push('CREATE TABLE IF NOT EXISTS `' + reflexiveTableName + '` (' + parts.join(',') + ')')
    return sqls

  createMigrationQueries:(migration)->
    sqls = []
    entityChangedNames = {}
    modelTo = migration.modelTo
    modelFrom = migration.modelFrom

    for change in migration.entitiesChanges
      entityName = change.entity
      switch change.change
        when '+'
          sqls = sqls.concat(@createEntityQueries(modelTo.getEntity(entityName)))
        when '-'
          sqls.push('DROP TABLE IF EXISTS ' + @quoteSymbol + @_formatTableName(entityName) + @quoteSymbol)
        else
          entityChangedNames[change.change] = entityName
          sqls.push('ALTER TABLE ' + @quoteSymbol + @_formatTableName(entityName) + @quoteSymbol + ' RENAME TO ' + @quoteSymbol + @_formatTableName(change.change) + @quoteSymbol)

    updatedEntities = _.uniq(Object.keys(migration.attributesChanges).concat(Object.keys(migration.relationshipsChanges)))

    for entityName in updatedEntities
      entityTo = modelTo.getEntity(entityName) or modelTo.getEntity(entityChangedNames[entityName])
      entityFrom = modelFrom.getEntity(entityName) or modelFrom.getEntity(entityChangedNames[entityName])

      oldColumnNames = ['_id']
      newColumnNames = ['_id']

      for attribute in entityFrom.getNonTransientAttributes()
        change = migration.attributesChanges[entityName]?[attribute.name]
        if change
          if change not in ['-','+']
            oldColumnNames.push(attribute.name)
            newColumnNames.push(change)
        else if change isnt '+'
          try
            newAttribute = entityTo.getAttribute(attribute.name)
            oldColumnNames.push(attribute.name)
            newColumnNames.push(newAttribute.name)
          catch e
            throw new Error('attribute ' + entityFrom.name + '->' + attribute.name + ' not found in version ' + modelFrom.migrateVersions)
      for attribute in entityTo.getNonTransientAttributes()
        change = migration.attributesChanges[entityName]?[attribute.name]
        if change is '+'
          try
            newColumnNames.push(attribute.name)
            oldColumnNames.push(null)
          catch e
            throw new Error('attribute ' + entityFrom.name + '->' + attribute.name + ' not found in version ' + modelFrom.migrateVersions)

      for relationship in entityFrom.relationships
        if not relationship.toMany
          change = migration.relationshipsChanges[entityName]?[relationship.name]
          if change
            if change not in ['-','+']
              oldColumnNames.push(relationship.name + '_id')
              newColumnNames.push(change + '_id')
          else if change isnt '+'
            try
              newRelationship = entityTo.getRelationship(relationship.name)
              oldColumnNames.push(relationship.name + '_id')
              newColumnNames.push(newRelationship.name + '_id')
            catch e
              throw new Error('relationship ' + entityFrom.name + '->' + relationship.name + ' not found in version ' + modelFrom.migrateVersions)
      for relationship in entityTo.relationships
        if not relationship.toMany
          change = migration.relationshipsChanges[entityName]?[relationship.name]
          if change is '+'
            try
              newColumnNames.push(relationship.name + '_id')
              oldColumnNames.push(null)
            catch e
              throw new Error('relationship ' + entityFrom.name + '->' + relationship.name + ' not found in version ' + modelFrom.migrateVersions)

      tableName = @quoteSymbol + @_formatTableName(entityName) + @quoteSymbol
      tmpTableName = @quoteSymbol + @_formatTableName(entityName) + '_tmp' + @quoteSymbol
      #      sqls.push('DROP TABLE IF EXISTS ' + tmpTableName)
      sqls.push('ALTER TABLE ' + tableName + ' RENAME TO ' + tmpTableName)
      sqls = sqls.concat(@createEntityQueries(entityTo,no,{ignoreRelationships:yes}))
      sqls.push('INSERT INTO ' + tableName + ' (' + @quoteSymbol + newColumnNames.join(@quoteSymbol + ',' + @quoteSymbol) + @quoteSymbol + ') SELECT ' + @quoteSymbol + oldColumnNames.join(@quoteSymbol + ',' + @quoteSymbol) + @quoteSymbol + ' FROM ' + tmpTableName)
      sqls.push('DROP TABLE ' + tmpTableName)

      for relationship in entityTo.relationships
        inversedRelationship = relationship.inverseRelationship()
        if relationship.toMany and inversedRelationship.toMany
          change = migration.relationshipsChanges[entityName]?[relationship.name]
          if change
            if change not in ['+','-']
              oldRelationship = entityFrom.getRelationship(change)
              oldInversedRelationship = oldRelationship.inverseRelationship()
              oldReflexiveRelationship = @_relationshipByPriority(oldRelationship,oldInversedRelationship)
              reflexiveRelationship = @_relationshipByPriority(relationship,inversedRelationship)
              oldReflexiveTableName = @quoteSymbol + @_formatTableName(oldReflexiveRelationship.entity.name) + '_' + oldReflexiveRelationship.name + @quoteSymbol
              reflexiveTableName = @quoteSymbol + @_formatTableName(reflexiveRelationship.entity.name) + '_' + reflexiveRelationship.name + @quoteSymbol

              #            sqls.push('DROP TABLE IF EXISTS ' + reflexiveTableName)
              sqls.push('ALTER TABLE ' + oldReflexiveTableName + ' RENAME TO ' + reflexiveTableName)
          else
            sqls = sqls.concat(@createEntityRelationshipQueries(entityTo))


    return sqls

class SQLiteConnection extends SQLConnection
  connect:(callback)->
    @connection = new sqlite.Database(@url.replace('sqlite://',''),(err)=>
      return callback(err) if err
      callback(null,@connection)
    )

  close:()->
    @connection.close()

  execute:(query,callback)->
    @connection.all(query,callback)

  createRow:(tableName,callback)->
    query = 'INSERT INTO `' + tableName + '` (`_id`) VALUES (NULL)'
    @log(query)
    @connection.run(query,(err)->
      return callback(err) if err
      callback(null,@lastID)
    )


module.exports = SQLiteStore;