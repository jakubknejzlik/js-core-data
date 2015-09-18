GenericSQLStore = require('./GenericSQLStore')
PersistentStoreRequest = require('./../PersistentStoreRequest')
GenericPool = require('generic-pool')
async = require('async')
ManagedObjectID = require('./../../ManagedObjectID')
Predicate = require('./../../FetchClasses/Predicate')

try
  require('mysql')
catch e
  throw new Error('mysql module is required to user MySQL storage, please install it by running npm install --save mysql')

mysql = require('mysql')

_ = require('underscore');
_.mixin(require('underscore.inflections'));


class MySQLStore extends GenericSQLStore
  createConnection:()->
    return new MySQLConnection(@URL,this)

  syncSchema: (options,callback)->
    if typeof options is 'function'
      callback = options
      options = null
    options = options or {}
    objectModel = @storeCoordinator.objectModel
    schema = {}
    sqls = []

    for key,entity of objectModel.entities
      tableName = @_formatTableName(entity.name)
      parts = ['`_id` int(11) NOT NULL AUTO_INCREMENT','PRIMARY KEY (`_id`)']

      for attribute in entity.attributes
        columnDefinition = @_columnDefinitionForAttribute(attribute)
        if columnDefinition
          parts.push(columnDefinition);
        else
          return callback(new Error('unknown attribute type ' + attribute.type))

      for relationship in entity.relationships
        if not relationship.toMany
          parts.push('`'+relationship.name+'_id` int(11) DEFAULT NULL')

      if options.force
        sqls.push('DROP TABLE IF EXISTS `' + tableName + '`')
      sql = 'CREATE TABLE IF NOT EXISTS `' + tableName + '` ('
      sql += parts.join(',')
      sql += ') ENGINE=InnoDB  DEFAULT CHARSET=utf8;'
      schema[tableName] = sql

      for key,relationship of entity.relationships
        if relationship.toMany
          inversedRelationship = relationship.inverseRelationship()
          if inversedRelationship.toMany
            reflexiveRelationship = @_relationshipByPriority(relationship,inversedRelationship)
            reflexiveTableName = @_formatTableName(reflexiveRelationship.entity.name) + '_' + reflexiveRelationship.name
            if options.force
              sqls.push('DROP TABLE IF EXISTS `' + reflexiveTableName  + '`')
            schema[reflexiveTableName] = 'CREATE TABLE IF NOT EXISTS `' + reflexiveTableName + '` (`'+reflexiveRelationship.name+'_id` int(11) NOT NULL,`reflexive` int(11) NOT NULL, PRIMARY KEY (`'+reflexiveRelationship.name+'_id`,`reflexive`))'

    for key,sql of schema
      sqls.push(sql);
    async.forEachSeries(sqls,(sql,cb)=>
        @connection.sendRawQuery(sql,cb)
      ,(err)->
        if callback
          callback(err)
    )


class MySQLConnection extends Object
  constructor: (url,@store,settings)->
    @pool = GenericPool.Pool({
      name     : "mysql",
      create   : (callback)->
        connection = mysql.createConnection(url,{multipleStatements:yes})
        connection.connect (err)->
          callback(err,connection)
      destroy  : (connection)->
        connection.destroy()
      max : settings?.maxConnections or (if process.NODE_ENV is 'production' then 100 else 10),
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
        q = conn.query(query,params,(err,result,fields)=>
          @pool.release(conn)
          callback?(err,result,fields)
        )
        @store.globals?.logging(q.sql) if @store.globals?.logging
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

  ensureBegin: (callback)->
    if @started
      return callback()
    @started = true
    if @store?.globals?.logging
      @store.globals.logging('BEGIN')
    @connection.query 'BEGIN',(err)->
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

      query = @connection.query(q,params,callback);

      if @store?.globals?.logging
        @store.globals.logging(query.sql)


  commit: (callback)->
    if @store?.globals?.logging
      @store.globals.logging('COMMIT')
    @connection.query('COMMIT',callback);

  rollback: (callback)->
    if @store?.globals?.logging
      @store.globals.logging('ROLLBACK')
    @connection.query('ROLLBACK',callback);


module.exports = MySQLStore;