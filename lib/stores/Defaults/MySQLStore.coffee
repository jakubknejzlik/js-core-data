IncrementalStore = require('./../IncrementalStore')
PersistentStoreRequest = require('./../PersistentStoreRequest')
GenericPool = require('generic-pool')
mysql = require('mysql')
async = require('async')
ManagedObjectID = require('./../../ManagedObjectID')
Predicate = require('./../../FetchClasses/Predicate')

_ = require('underscore');
_.mixin(require('underscore.inflections'));


class MySQLStore extends IncrementalStore
  constructor: (@storeCoordinator,@URL)->
    @connection = new MySQLConnection(@URL,this)
    @fetchedObjectValuesCache = {}
    @permanentIDsCache = {}
    @debug = no

  execute:(request,context,callback,afterInsertCallback) ->
    if request not instanceof  PersistentStoreRequest
      throw new Error('request ' + request + ' is not instance of PersistentStoreRequest')

    if request.type is 'save'
      @connection.createTransaction (transaction)=>
        transaction.debug = @debug
        async.series [
          (seriesCallback)=> async.forEach request.insertedObjects,
            (insertedObject,cb)=>
              formattedTableName = @_formatTableName(insertedObject.entity.name)
              inserts = ['`_id` = NULL']
#              for key,value of values
#                inserts.push('`' + key + '` = ' + mysql.escape(value))
              sql = 'INSERT INTO ' + formattedTableName + ' SET ' + inserts.join(',')
              transaction.sendQuery sql,(err,result)=>
                if err
                  return cb(err)
                @permanentIDsCache[insertedObject.objectID.toString()] = result.insertId
                cb()
            ,(err)=>
              afterInsertCallback();
              seriesCallback(err)
          (seriesCallback)=> async.forEach request.insertedObjects,
            (insertedObject,cb)=>
              formattedTableName = @_formatTableName(insertedObject.entity.name)
              values = @_valuesWithRelationshipsForObject(insertedObject)
              id = @_recordIDForObjectID(insertedObject.objectID);
              updates = []
              for key,value of values
                updates.push('`' + key + '` = ' + mysql.escape(value))
              if updates.length > 0
                sql = 'UPDATE `' + formattedTableName + '` SET ' + updates.join(',') + ' WHERE `_id` = ' + mysql.escape(id);
                transaction.sendQuery sql,(err,result)=>
                  if err
                    return cb(err)
                  @_updateRelationsForObject(transaction,insertedObject,cb)
              else @_updateRelationsForObject(transaction,insertedObject,cb)
            ,seriesCallback
          (seriesCallback)=> async.forEach request.updatedObjects,
            (updatedObject,cb)=>
              formattedTableName = @_formatTableName(updatedObject.entity.name)
              id = @_recordIDForObjectID(updatedObject.objectID);
              values = @_valuesWithRelationshipsForObject(updatedObject)
              updates = []
              for key,value of values
                updates.push('`' + key + '` = ' + mysql.escape(value))
#              console.log('updated',updates,values)
              if updates.length > 0
                sql = 'UPDATE `' + formattedTableName + '` SET ' + updates.join(',') + ' WHERE `_id` = ' + mysql.escape(id);
                transaction.sendQuery sql,(err)=>
                  if err
                    return cb(err)
                  @_updateRelationsForObject(transaction,updatedObject,cb)
              else @_updateRelationsForObject(transaction,updatedObject,cb)
            ,(err)=>
              seriesCallback(err)
          (seriesCallback)=> async.forEach request.deletedObjects,
            (deletedObject,cb)=>
              formattedTableName = @_formatTableName(deletedObject.entity.name)
              id = @_recordIDForObjectID(deletedObject.objectID);
              sql = 'DELETE FROM `' + formattedTableName + '` WHERE `_id` = ' + mysql.escape(id)
              transaction.sendQuery sql,(err)->
                cb(err)
            ,(err)=>
              seriesCallback(err)
          ],(err)=>
            if err
              return transaction.rollback (rollbackError)->
                callback(err)
            transaction.commit (err)=>
              @connection.releaseTransaction(transaction)
              callback(err)

    if request.type is 'fetch'
#      console.log('sql fetch',@_sqlForFetchRequest(request))
      @connection.sendRawQuery @_sqlForFetchRequest(request),(err,rows)=>
        ids = []
        return callback(err) if err
        for row in rows
          _row = {}
          for attribute in request.entity.attributes
            _row[attribute.name] = row[attribute.name]
#          for relationship in request.entity.relationships
#            if not relationship.toMany
#              _row[relationship.name] = if row[relationship.name] then @_permanentIDForRecord(relationship.destinationEntity,row[relationship.name]) else null
          objectID = @_permanentIDForRecord(request.entity,row._id)
          @fetchedObjectValuesCache[objectID.toString()] = _row;
          ids.push(objectID)
        callback(null,ids)

  _sqlForFetchRequest: (request) ->
    columns = ['`_id` as `_id`']
    for attribute in request.entity.attributes
      columns.push('`' + attribute.name + '` as `' + attribute.name + '`')
    sql = 'SELECT ' + columns.join(',') + ' FROM `' + @_formatTableName(request.entity.name) + '` SELF';
    if request.predicate instanceof Predicate
      sql += ' WHERE ' + request.predicate.toString();
#      sql += ' WHERE `_id` = ' + mysql.escape(@_recordIDForObjectID(request.predicate));
    else if request.predicate
      sql += ' WHERE ' + request.predicate

    if request.sortDescriptors
      descriptors = request.sortDescriptors
      if descriptors and not Array.isArray(descriptors)
        descriptors = [descriptors]
#      if typeof descriptors is 'string'
#        descriptors = descriptors.split(',');
        sql += ' ORDER BY ';
        keys = [];
        for key in descriptors
          keys.push(key.toString())
        sql += keys.join(',');
#        console.log('desc',keys,sql);

    sql

  _updateRelationsForObject: (transaction,object,callback)->
    sqls = []
    for relationship in object.entity.relationships
      inversedRelationship = relationship.inverseRelationship()
      reflexiveRelationship = @_relationshipByPriority(relationship,inversedRelationship);
#      if reflexiveRelationship != relationship
#        inversedRelationship = relationship
#        relationship = reflexiveRelationship
      if relationship.toMany and inversedRelationship.toMany and object._relationChanges and relationship is reflexiveRelationship
#        console.log('update relationship',object.entity.name,relationship.name,object._relationChanges)
        addedObjects = object._relationChanges?['added_' + relationship.name]
        #        console.log(relationship.name,inversedRelationship.name,Object.keys(object.relationChanges),'added_' + relationship.name)
        if addedObjects
          for addedObject in addedObjects
#          console.log('xxxxx',object.relationChanges);
            sql = 'INSERT INTO `' + @_formatTableName(relationship.entity.name) + '_' + relationship.name + '` SET reflexive = ' + mysql.escape(@_recordIDForObjectID(object.objectID)) + ',`' + relationship.name + '_id` = ' + mysql.escape(@_recordIDForObjectID(addedObject.objectID))
            sqls.push(sql)

        removedObjects = object._relationChanges?['removed_' + relationship.name]
        #        console.log(relationship.name,inversedRelationship.name,Object.keys(object.relationChanges),'added_' + relationship.name)
        if removedObjects
          for removedObject in removedObjects
#          console.log('xxxxx',object.relationChanges);
            sql = 'DELETE FROM `' + @_formatTableName(relationship.entity.name) + '_' + relationship.name + '` WHERE reflexive = ' + mysql.escape(@_recordIDForObjectID(object.objectID)) + ' AND `' + relationship.name + '_id` = ' + mysql.escape(@_recordIDForObjectID(removedObject.objectID))
            sqls.push(sql)
    async.forEachSeries sqls,(sql,cb)->
      transaction.sendQuery(sql,cb)
    ,callback

  _valuesWithRelationshipsForObject:(object)->
    data = {}
    for key,value of object._changes
      data[key] = value;
#    console.log('xxx',object.entity.name)
    for relation in object.entity.relationships
      if not relation.toMany
        if object._relationChanges?[relation.name] isnt undefined
          if object._relationChanges?[relation.name]
            id = @_recordIDForObjectID(object._relationChanges[relation.name].objectID);
            data[relation.name + '_id'] = id
          else
            data[relation.name + '_id'] = null
    return data;

  valuesForObject:(ObjectID,context) ->
#    console.log('fetching data',ObjectID.toString(),@fetchedObjectValuesCache[ObjectID.toString()])
    @fetchedObjectValuesCache[ObjectID.toString()] or {}

  valuesForRelationship:(relationship,ObjectID,context,callback) ->
    inversedRelationship = relationship.inverseRelationship()
    sql = null
    columns = ['`_id` as _id']
    for attribute in relationship.destinationEntity.attributes
      columns.push('`' + attribute.name + '` as ' + attribute.name)
    mainRelationship = @_relationshipByPriority(relationship,inversedRelationship)
#    console.log(relationship.name,'=>',relationship.toMany,' ',mainRelationship.name,inversedRelationship.name)
    if relationship.toMany and inversedRelationship.toMany
      if mainRelationship is relationship
        sql = 'SELECT ' + columns.join(',') + ' FROM `' + @_formatTableName(relationship.destinationEntity.name) + '` WHERE `_id` IN (SELECT `' + relationship.name + '_id` FROM `' + @_formatTableName(relationship.entity.name) + '_' + relationship.name + '` WHERE `reflexive` = ' + mysql.escape(@_recordIDForObjectID(ObjectID)) + ')'
      else
        sql = 'SELECT ' + columns.join(',') + ' FROM `' + @_formatTableName(relationship.destinationEntity.name) + '` WHERE `_id` IN (SELECT `reflexive` FROM `' + @_formatTableName(inversedRelationship.entity.name) + '_' + inversedRelationship.name + '` WHERE `' + inversedRelationship.name + '_id` = ' + mysql.escape(@_recordIDForObjectID(ObjectID)) + ')'
#      console.log('sql!!??',relationship.name,sql)
    else
#      if mainRelationship is relationship
        if inversedRelationship.toMany
          sql = 'SELECT ' + columns.join(',') + ' FROM `' + @_formatTableName(relationship.destinationEntity.name) + '` WHERE `_id` IN (SELECT `' + relationship.name + '_id` FROM `' + @_formatTableName(relationship.entity.name) + '` WHERE `_id` = ' + mysql.escape(@_recordIDForObjectID(ObjectID)) + ') LIMIT 1'
        else
          sql = 'SELECT ' + columns.join(',') + ' FROM `' + @_formatTableName(relationship.destinationEntity.name) + '` WHERE `' + inversedRelationship.name + '_id` = ' + mysql.escape(@_recordIDForObjectID(ObjectID))
#      else
#        if relationship.toMany
#          sql = 'SELECT ' + columns.join(',') + ' FROM `' + @_formatTableName(relationship.destinationEntity.name) + '` WHERE `' + inversedRelationship.name + '_id` = ' + mysql.escape(@_recordIDForObjectID(ObjectID))
#        else
#          sql = 'SELECT ' + columns.join(',') + ' FROM `' + @_formatTableName(relationship.destinationEntity.name) + '` WHERE `_id` IN (SELECT `' + relationship.name + '_id` FROM `' + @_formatTableName(relationship.entity.name) + '` WHERE `_id` = ' + mysql.escape(@_recordIDForObjectID(ObjectID)) + ')'
#      console.log('sql!!',relationship.name,sql)

    @connection.sendRawQuery sql,(err,rows)=>
      ids = []
      return callback(err) if err
      for row in rows
        _row = {}
        for attribute in relationship.destinationEntity.attributes
          _row[attribute.name] = row[attribute.name]
        objectID = @_permanentIDForRecord(relationship.destinationEntity,row._id)
        @fetchedObjectValuesCache[objectID.toString()] = _row;
        ids.push(objectID)
      if relationship.toMany
        callback(null,ids)
      else
        callback(null,ids[0])
#    throw new Error('valuesForObjet method not implemented')


  permanentIDsForObjects:(objects,callback) ->
    ids = []
    for object in objects
      ids.push(@_permanentIDForRecord(object.entity,@permanentIDsCache[object.objectID.toString()]))
    ids

  newObjectID:(entity,referenceObject) ->
    new ManagedObjectID(@URL + '/' + entity.name + '/t' + referenceObject,entity)

  _permanentIDForRecord: (entity,referenceObject)->
    new ManagedObjectID(@URL + '/' + entity.name + '/p' + referenceObject,entity)

  _recordIDForObjectID: (objectID) ->
#    id = @permanentIDsCache[objectID.toString()]
#    if id
#      return id
#    console.log(@permanentIDsCache,objectID.toString())
    objectID.recordId()
#    components = objectID.toString().split('/')
#    components[components.length - 1].replace(/^[pt]/,'')


  buildSchema: (callback)->
    objectModel = @storeCoordinator.objectModel
    schema = {}
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


      sql = 'CREATE TABLE IF NOT EXISTS `' + tableName + '` ('
      sql += parts.join(',');
      sql += ') ENGINE=InnoDB  DEFAULT CHARSET=utf8;'
      schema[tableName] = sql;

      for key,relationship of entity.relationships
        if relationship.toMany
          inversedRelationship = relationship.inverseRelationship()
          if inversedRelationship.toMany
            reflexiveRelationship = @_relationshipByPriority(relationship,inversedRelationship)
            reflexiveTableName = @_formatTableName(reflexiveRelationship.entity.name) + '_' + reflexiveRelationship.name
            schema[reflexiveTableName] = 'CREATE TABLE IF NOT EXISTS `' + reflexiveTableName + '` (`'+reflexiveRelationship.name+'_id` int(11) NOT NULL,`reflexive` int(11) NOT NULL, PRIMARY KEY (`'+reflexiveRelationship.name+'_id`,`reflexive`))'

    sqls = []
    for key,sql of schema
      sqls.push(sql);
    async.forEachSeries sqls,(sql,cb)=>
      @connection.sendRawQuery(sql,cb)
    ,(err)->
      if callback
        callback(err)

  _relationshipByPriority: (relationship,inversedRelationship)->
    if relationship.name > inversedRelationship.name
      return relationship
    return inversedRelationship

  _formatTableName: (name)->
    return _.pluralize(name).toLowerCase()

  _columnDefinitionForAttribute:(attribute)->
    type = null
    defaultValue = attribute.info.default or 'NULL'
    switch attribute.type
      when 'bool','boolean'
        type = 'tinyint(1)'
      when 'string','email','url'
        type = 'varchar(' + (attribute.options.length or 255) + ')'
      when 'text'
        if attribute.options.length
          if attribute.options.length < 256
            type = 'tinytext'
          else if attribute.options.length < 65536
            type = 'text'
          else if attribute.options.length < 16777216
            type = 'mediumtext'
          else if attribute.options.length < 4294967296
            type = 'longtext'
        else
          type = 'longtext'
      when 'data'
        if attribute.options.length
          if attribute.options.length < 256
            type = 'tinyblob'
          else if attribute.options.length < 65536
            type = 'blob'
          else if attribute.options.length < 16777216
            type = 'mediumblob'
          else if attribute.options.length < 4294967296
            type = 'longblob'
        else
          type = 'longblob'
      when 'int','integer'
        type = 'int('+(attribute.options.length or 11)+')'
      when 'decimal'
        type = 'decimal('+(attribute.options.digits or 20)+','+(attribute.options.decimals or 5)+')'
      when 'float'
        type = 'float'
      when 'double'
        type = 'double'
      when 'date'
        type = 'datetime'
      when 'timestamp'
        type = 'bigint(20)'
      else return null
    definition = '`'+attribute.name+'` '+type+' DEFAULT '+defaultValue
    if attribute.info.unique
      definition += ', UNIQUE(`'+attribute.name+'`)'
    return definition




class MySQLConnection extends Object
  constructor: (url,@store,settings)->
    @pool = GenericPool.Pool({
      name     : "mysql",
      create   : (callback)->
        connection = mysql.createConnection(url)
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
        q = conn.query query,params,(err,result,fields)=>
          @pool.release(conn)
          callback?(err,result,fields)
        console.log(q.sql) if @store.debug
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
    @pool.acquire (err,connection)->
      if err
        return callback(err)
      callback(new Transaction(connection))

  releaseTransaction: (transaction)->
    @pool.release(transaction.connection);

class Transaction extends Object
  constructor:(@connection)->
    @started = false;
    @autoRollback = true;
    @debug = no

  ensureBegin: (callback)->
    if @started
      return callback()
    @started = true
    @connection.query 'BEGIN',(err)->
      callback(err)

  sendQuery: (query,callback)->
    if not @connection
      throw new Error('connection released or not set');

    q = if typeof query is 'string' then query else query.getSQL();
    @ensureBegin (err)=>
      if err
        if self.autoRollback
          return @rollback ()->
            callback(err)
        else return callback(err)

      if @debug
        console.log(q)

      @connection.query(q,callback);

  commit: (callback)->
    @connection.query('COMMIT',callback);

  rollback: (callback)->
    @connection.query('ROLLBACK',callback);


module.exports = MySQLStore;