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


class SQLiteStore extends GenericSQLStore
  createConnection:(url)->
    return new SQLiteConnection(url,@)

  createSchemaQueries: (options = {})->
    objectModel = @storeCoordinator.objectModel
    sqls = []

    for key,entity of objectModel.entities
      sqls = sqls.concat(@createEntityQueries(entity,options.force))

    sqls.push('CREATE TABLE IF NOT EXISTS `_meta` (`key` varchar(10) NOT NULL,`value` varchar(250) NOT NULL,PRIMARY KEY (`key`))')
    sqls.push('INSERT OR IGNORE INTO `_meta` VALUES(\'version\',\'' + objectModel.version + '\')')

    return sqls

  createEntityQueries:(entity,force = no,options = {})->
    sqls = []
    tableName = @_formatTableName(entity.name)
    parts = ['`_id` INTEGER PRIMARY KEY AUTOINCREMENT']

    for attribute in entity.attributes
      columnDefinition = @_columnDefinitionForAttribute(attribute)
      if columnDefinition
        parts.push(columnDefinition);
      else
        throw new Error('unknown attribute type ' + attribute.type)

    for relationship in entity.relationships
      if not relationship.toMany
        parts.push('`'+relationship.name+'_id` int(11) DEFAULT NULL')

    if force
      sqls.push('DROP TABLE IF EXISTS `' + tableName + '`')
    sql = 'CREATE TABLE IF NOT EXISTS `' + tableName + '` ('
    sql += parts.join(',')
    sql += ')'

    for index in @_indexesForEntity(entity)
      sql +=";CREATE " + (if index.type is 'unique' then 'UNIQUE' else '') + " INDEX IF NOT EXISTS `"+index.name+'` ON `'+tableName+'` (`'+index.columns.join('`,`')+"`)"

    sqls.push(sql)

    if not options.ignoreRelationships
      console.log(@createEntityRelationshipQueries)
      sqls = sqls.concat(@createEntityRelationshipQueries(entity,force))

    return sqls

  createRelationshipQueries:(relationship,force)->
    sqls = []
    if relationship.toMany
      inversedRelationship = relationship.inverseRelationship()
      if inversedRelationship.toMany
        reflexiveRelationship = @_relationshipByPriority(relationship,inversedRelationship)
        reflexiveTableName = @_getMiddleTableNameForManyToManyRelation(reflexiveRelationship)
        if force
          sqls.push('DROP TABLE IF EXISTS `' + reflexiveTableName  + '`')
        sqls.push('CREATE TABLE IF NOT EXISTS `' + reflexiveTableName + '` (`'+reflexiveRelationship.name+'_id` int(11) NOT NULL,`reflexive` int(11) NOT NULL, PRIMARY KEY (`'+reflexiveRelationship.name+'_id`,`reflexive`))')
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

      for attribute in entityTo.attributes
        change = migration.attributesChanges[entityName]?[attribute.name]
        if change
          if change not in ['-','+']
            newColumnNames.push(attribute.name)
            oldColumnNames.push(change)
        else
          try
            oldAttribute = entityFrom.getAttribute(attribute.name)
            newColumnNames.push(attribute.name)
            oldColumnNames.push(oldAttribute.name)
          catch e
            throw new Error('attribute ' + entityFrom.name + '->' + attribute.name + ' not found in version ' + modelFrom.version)

      for relationship in entityTo.relationships
        if not relationship.toMany
          change = migration.relationshipsChanges[entityName]?[relationship.name]
          if change
            if change not in ['-','+']
              newColumnNames.push(relationship.name + '_id')
              oldColumnNames.push(change + '_id')
          else
            try
              oldRelationship = entityFrom.getRelationship(relationship.name)
              newColumnNames.push(relationship.name + '_id')
              oldColumnNames.push(oldRelationship.name + '_id')
            catch e
              throw new Error('relationship ' + entityFrom.name + '->' + relationship.name + ' not found in version ' + modelFrom.version)

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
    query = 'INSERT INTO ' + tableName+ ' (`_id`) VALUES (NULL)'
    @log(query)
    @connection.run(query,(err)->
      return callback(err) if err
      callback(null,@lastID)
    )


module.exports = SQLiteStore;