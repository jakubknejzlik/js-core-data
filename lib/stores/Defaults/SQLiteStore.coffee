GenericSQLStore = require('./GenericSQLStore')
PersistentStoreRequest = require('./../PersistentStoreRequest')
GenericPool = require('generic-pool')
async = require('async')
ManagedObjectID = require('./../../ManagedObjectID')
Predicate = require('./../../FetchClasses/Predicate')

try
  require('sqlite3')
catch e
  throw new Error('sqlite3 module is required to user SQLite storage, please install it by running npm install --save sqlite3')

sqlite = require('sqlite3')

_ = require('underscore');
_.mixin(require('underscore.inflections'));


class SQLiteStore extends GenericSQLStore
  createConnection:()->
    return new SQLiteConnection(@URL,this)

  createSchemaQueries: (options = {})->
    objectModel = @storeCoordinator.objectModel
#    schema = {}
    sqls = []

    for key,entity of objectModel.entities
      sqls = sqls.concat(@createEntityQueries(entity,options.force))
#    for key,sql of schema
#      sqls.push(sql);

    sqls.push('CREATE TABLE IF NOT EXISTS `_meta` (`key` varchar(10) NOT NULL,`value` varchar(250) NOT NULL,PRIMARY KEY (`key`))')
    sqls.push('INSERT OR IGNORE INTO `_meta` VALUES(\'version\',\'' + objectModel.version + '\')')

    return sqls

  createEntityQueries:(entity,force = no)->
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
      sql +=";CREATE INDEX IF NOT EXISTS `"+index.name+'` ON `'+tableName+'` (`'+index.columns.join('`,`')+"`)"

    sqls.push(sql)

    for key,relationship of entity.relationships
      if relationship.toMany
        inversedRelationship = relationship.inverseRelationship()
        if inversedRelationship.toMany
          reflexiveRelationship = @_relationshipByPriority(relationship,inversedRelationship)
          reflexiveTableName = @_formatTableName(reflexiveRelationship.entity.name) + '_' + reflexiveRelationship.name
          if force
            sqls.push('DROP TABLE IF EXISTS `' + reflexiveTableName  + '`')
          sqls.push('CREATE TABLE IF NOT EXISTS `' + reflexiveTableName + '` (`'+reflexiveRelationship.name+'_id` int(11) NOT NULL,`reflexive` int(11) NOT NULL, PRIMARY KEY (`'+reflexiveRelationship.name+'_id`,`reflexive`))')

    return sqls


  createMigrationQueries:(migration)->
#    console.log('migration',migration)
    sqls = []
    modelTo = migration.modelTo
    modelFrom = migration.modelFrom

    for entityName,change of migration.entitiesChanges
      switch change
        when '+'
          sqls = sqls.concat(@createEntityQueries(modelTo.getEntity(entityName)))
        when '-'
          sqls.push('DROP TABLE IF EXISTS `' + @_formatTableName(entityName) + '`')
        else
          sqls.push('ALTER TABLE `' + @_formatTableName(change) + '` RENAME TO `' + @_formatTableName(entityName) + '`')


    for entityName,attributes of migration.attributesChanges
      entity = modelTo.getEntity(entityName)
      for attributeName,change of attributes
        attribute = entity.getAttribute(attributeName)
        switch change
          when '+'
            sqls.push('ALTER TABLE `' + @_formatTableName(entityName) + '` ADD COLUMN ' + @_columnDefinitionForAttribute(attribute))
          when '-'
            throw new Error('drop column not implemented in sqlite3')
#            sqls.push('DROP TABLE IF EXISTS `' + @_formatTableName(entity.name) + '`')
          else
            throw new Error('rename column not implemented in sqlite3')
#            sqls.push('ALTER TABLE `' + @_formatTableName(change) + '` RENAME TO `' + @_formatTableName(entity.name) + '`')

    for entityName,relationships of migration.relationshipsChanges
      entity = modelTo.getEntity(entityName)
      oldEntity = modelFrom.getEntity(entityName)
      for relationshipName,change of relationships
        relationship = entity.getRelationship(relationshipName)
        inverseRelationship = relationship.inverseRelationship()
        if inverseRelationship.toMany
          [relationship,inverseRelationship] = [inverseRelationship,relationship]
        if relationship.toMany and inverseRelationship.toMany
          reflexiveRelationship = @_relationshipByPriority(relationship,inverseRelationship)
          reflexiveTableName = @_formatManyToManyRelationshipTableName(relationship)
          switch change
            when '+'
              sqls.push('CREATE TABLE IF NOT EXISTS `' + reflexiveTableName + '` (`'+reflexiveRelationship.name+'_id` int(11) NOT NULL,`reflexive` int(11) NOT NULL, PRIMARY KEY (`'+reflexiveRelationship.name+'_id`,`reflexive`))')
            when '-'
              sqls.push('DROP TABLE IF EXISTS `' + reflexiveTableName  + '`')
            else
              oldRelationship = oldEntity.getRelationship(change)
              oldReflexiveTableName = @_formatManyToManyRelationshipTableName(oldRelationship)
              sqls.push('ALTER TABLE `' + oldReflexiveTableName+ '` RENAME TO `' + reflexiveTableName + '`')
        else if relationship.toMany
          switch change
            when '+'
              sqls.push('ALTER TABLE `' + @_formatTableName(entity.name) + '` ADD COLUMN `'+relationship.name+'_id` int(11) DEFAULT NULL')
            when '-'
              throw new Error('drop relationship oneToMany not implemented in sqlite3')
            else
              throw new Error('rename relationship oneToMany not implemented in sqlite3')

    return sqls



class SQLiteConnection extends Object
  constructor: (url,@store,settings)->
    @pool = GenericPool.Pool({
      name     : "sqlite",
      create   : (callback)=>
        connection = new sqlite.Database(url.replace('sqlite://',''),(err)=>
          connection.on('trace',(query)=>
            if @store?.globals?.logging
              @store.globals.logging(query)
          )
          callback(err,connection)
        )
      destroy  : (connection)->
        connection.close()
      max : 1 #settings?.maxConnections or (if process.NODE_ENV is 'production' then 100 else 10),
      idleTimeoutMillis : settings?.idletimeoutMillis ? 60*1000,
      reapIntervalMillis : settings?.reapIntervalMillis ? 5*1000
    })

  sendRawQuery: (query,params,callback)=>
    if typeof params is 'function'
      callback = params
      params = null
    @pool.acquire (err,conn)=>
      return callback?(err) if err
      try
        params = params or {}
        conn.all(query,params,(err,results)=>
          @pool.release(conn)
          callback?(err,results)
        )
#        @store.globals.logging(query) if @store.globals?.logging
      catch error
        @pool.release(conn)
        callback?(error)

  sendQuery: (query,params,callback)->
    if typeof params is 'function'
      callback = params
      params = null
    try
      sql = query.getSQL();
      @sendRawQuery(sql,params,callback);
    catch err
      callback(err)

  createTransaction: (callback)->
#    console.log('acquire connection');
    @pool.acquire (err,connection)=>
      if err
        return callback(err)
      callback(new Transaction(connection,@store))

  releaseTransaction: (transaction)->
    @pool.release(transaction.connection);

class Transaction extends Object
  constructor:(@connection,@store)->
    @started = false;
    @autoRollback = true;
    @debug = no

  ensureBegin: (callback)->
    if @started
      return callback()
    @started = true
    @connection.run 'BEGIN',(err)->
      callback(err)

  sendQuery: (query,params,callback)->
    if typeof params is 'function'
      callback = params
      params = undefined
    if not @connection
      throw new Error('connection released or not set');

    q = if typeof query is 'string' then query else query.getSQL();
    @ensureBegin (err)=>
      if err
        if self.autoRollback
          return @rollback ()->
            callback(err)
        else return callback(err)

#      if @store?.globals?.logging
#        @store.globals.logging(q)

      params = params or {}
      @connection.run(q,params,(err,results)->
        results = results or {}
        results.insertId = @lastID
        callback(err,results) if callback
      );

  commit: (callback)->
    @connection.run('COMMIT',callback);

  rollback: (callback)->
    @connection.run('ROLLBACK',callback);


module.exports = SQLiteStore;