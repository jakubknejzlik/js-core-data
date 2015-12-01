IncrementalStore = require('./../IncrementalStore')
PersistentStoreRequest = require('./../PersistentStoreRequest')
#GenericPool = require('generic-pool')
async = require('async')
ManagedObjectID = require('./../../ManagedObjectID')
Predicate = require('./../../FetchClasses/Predicate')
FetchRequest = require('./../../FetchRequest')
SortDescriptor = require('./../../FetchClasses/SortDescriptor')
squel = require('squel')
moment = require('moment')

PersistentStoreCoordinator = require('../../PersistentStoreCoordinator')
ManagedObjectContext = require('../../ManagedObjectContext')

#AttributeTransformer = require('../../Helpers/AttributeTransformer')
SQLConnectionPool = require('./SQLConnectionPool')
_ = require('underscore');
_.mixin(require('underscore.inflections'));


class GenericSQLStore extends IncrementalStore
  @::tableAlias = 'SELF'
  @::quoteSymbol = '"'

  constructor: (@storeCoordinator,@URL,@globals)->
    if @storeCoordinator
      @connectionPool = new SQLConnectionPool(@URL,(url)=>
        return @createConnection(url)
      ,@,@globals)
    #      @connection = @createConnection()
    #    @fetchedObjectValuesCache = {}
    @permanentIDsCache = {}

  createConnection: (url)->
    throw new Error('createConnection must be overriden')

  execute:(request,context,callback,afterInsertCallback) ->
    if request not instanceof  PersistentStoreRequest
      throw new Error('request ' + request + ' is not instance of PersistentStoreRequest')

    if request.type is 'save'
      @connectionPool.createTransaction (err,transaction)=>
        return callback(err) if err
        async.series [
          (seriesCallback)=> async.forEach request.insertedObjects,
            (insertedObject,cb)=>
              formattedTableName = @_formatTableName(insertedObject.entity.name)
              #              inserts = ['`_id` = NULL']
              #              for key,value of values
              #                inserts.push('`' + key + '` = ' + mysql.escape(value))
              #              sql = 'INSERT INTO ' + formattedTableName + ' ('+@quoteSymbol+'_id'+@quoteSymbol+') VALUES (' + @DEFAULT_PRIMARY_KEY_VALUE + ') RETURNING "_id"'
              transaction.createRow(formattedTableName,(err,rowId)=>
                if err
                  return cb(err)
                @permanentIDsCache[insertedObject.objectID.toString()] = rowId
                cb()
              )
          ,(err)=>
            afterInsertCallback();
            seriesCallback(err)
          (seriesCallback)=> async.forEach request.deletedObjects,
            (deletedObject,cb)=>
              formattedTableName = @_formatTableName(deletedObject.entity.name)
              id = @_recordIDForObjectID(deletedObject.objectID);
              sql = 'DELETE FROM ' + @quoteSymbol + formattedTableName + @quoteSymbol + ' WHERE ' + @quoteSymbol + '_id' + @quoteSymbol + ' = ' + id
              transaction.query sql,(err)->
                cb(err)
          ,seriesCallback
          (seriesCallback)=> async.forEachSeries request.insertedObjects,
            (insertedObject,cb)=>
              [sql,updateValues] = @updateQueryForUpdatedObject(insertedObject)
              if sql
                transaction.query(sql,updateValues,(err)=>
                  if err
                    return cb(err)
                  @_updateRelationsForObject(transaction,insertedObject,cb)
                )
              else @_updateRelationsForObject(transaction,insertedObject,cb)
          ,seriesCallback
          (seriesCallback)=> async.forEachSeries request.updatedObjects,
            (updatedObject,cb)=>
              [sql,updateValues] = @updateQueryForUpdatedObject(updatedObject)
              if sql
                transaction.query(sql,updateValues,(err)=>
                  if err
                    return cb(err)
                  @_updateRelationsForObject(transaction,updatedObject,cb)
                )
              else @_updateRelationsForObject(transaction,updatedObject,cb)
          ,seriesCallback
        ],(err)=>
          if err
            return transaction.rollback(()=>
              @connectionPool.releaseTransaction(transaction)
              callback(err)
            )
          transaction.commit((err)=>
            @connectionPool.releaseTransaction(transaction)
            callback(err)
          )

    if request.type is 'fetch'
#      console.log('sql fetch',@_sqlForFetchRequest(request))
      @connectionPool.query(@sqlForFetchRequest(request),(err,rows)=>
        ids = []
        return callback(err) if err

        if request.resultType is FetchRequest.RESULT_TYPE.VALUES
          return callback(null,rows)

        objectValues = {}
        for row in rows
          _row = {}
          for attribute in request.entity.attributes
            _row[attribute.name] = row[attribute.name]
          for relationship in request.entity.relationships
            if not relationship.toMany
              columnName = _.singularize(relationship.name) + '_id'
              _row[columnName] = row[columnName]
          objectID = @_permanentIDForRecord(request.entity,row._id)
          #          @fetchedObjectValuesCache[objectID.toString()] = _row;
          for attribute in request.entity.attributes
            _row[attribute.name] = @decodeValueForAttribute(_row[attribute.name],attribute)
          objectValues[objectID.toString()] = _row;
          ids.push(objectID)
        callback(null,ids,objectValues)
      )

  numberOfObjectsForFetchRequest:(request,callback)->
    @connectionPool.query(@countSqlForFetchRequest(request),(err,result)=>
      callback(err,Number(result?[0]?.count))
    )

  updateQueryForUpdatedObject:(updatedObject)->
    formattedTableName = @_formatTableName(updatedObject.entity.name)
    id = @_recordIDForObjectID(updatedObject.objectID);
    values = @_valuesWithRelationshipsForObject(updatedObject)
    updates = []
    updateValues = []
    for key,value of values
      try
        attribute = updatedObject.entity.getAttribute(key)
      catch e
        attribute = null

      if attribute
        updates.push(@quoteSymbol + key + @quoteSymbol + ' = ?')
        updateValues.push(@encodeValueForAttribute(attribute.encode(value),attribute))
      else
        updates.push(@quoteSymbol + key + @quoteSymbol + ' = ?')
        updateValues.push(value)
    if updates.length > 0
      return ['UPDATE ' + @quoteSymbol + formattedTableName + @quoteSymbol + ' SET ' + updates.join(',') + ' WHERE ' + @quoteSymbol + '_id' + @quoteSymbol + ' = ' + id,updateValues]
    else
      return [null,null]


  countSqlForFetchRequest:(request)->
    query = squel.select({autoQuoteAliasNames:no}).from(@_formatTableName(request.entity.name),@tableAlias)
    query.field('COUNT(DISTINCT SELF._id)','count')
    if request.predicate
      query.where(@parsePredicate(request.predicate))
    sqlString = @_getRawTranslatedQueryWithJoins(query,request)
    return @processQuery(sqlString)

  sqlForFetchRequest: (request) ->
    query = squel.select({autoQuoteAliasNames:no}).from(@_formatTableName(request.entity.name),@tableAlias)

    if request.resultType is FetchRequest.RESULT_TYPE.MANAGED_OBJECTS
      query.group('SELF._id')
      query.field(@tableAlias + '.' + @quoteSymbol + '_id' + @quoteSymbol,@quoteSymbol + '_id' + @quoteSymbol)
      for attribute in request.entity.attributes
        query.field(@tableAlias + '.' + @quoteSymbol + attribute.name + @quoteSymbol,@quoteSymbol + attribute.name + @quoteSymbol)
      for relationship in request.entity.relationships
        if not relationship.toMany
          columnName = _.singularize(relationship.name) + '_id'
          query.field(@tableAlias + '.' + @quoteSymbol + columnName + @quoteSymbol,@quoteSymbol + columnName + @quoteSymbol)
    else
      if not request.fields
        query.field(@tableAlias + '.*')
      else
        for name,field of request.fields
          query.field(field,@quoteSymbol + name + @quoteSymbol)
      if request.group
        query.group(request.group)

    if request.predicate
      query.where(@parsePredicate(request.predicate))

    query.limit(request.limit) if request.limit
    query.offset(request.offset) if request.offset

    if Array.isArray(request.sortDescriptors) and request.sortDescriptors.length > 0
      descriptors = request.sortDescriptors
      for descriptor in descriptors
        column = descriptor.attribute
        if column.indexOf(@tableAlias + '.') is -1
          column = @tableAlias + '.' + column
        query.order(column,descriptor.ascending)


    sqlString = @_getRawTranslatedQueryWithJoins(query,request)
    return @processQuery(sqlString)


  parsePredicate:(predicate)->
    return predicate.toString()


  _getRawTranslatedQueryWithJoins:(query,request)->
    replaceNames = {}
    joins = {}

    sqlString = query.toString()

    clearedSQLString = sqlString.replace(/\\"/g,'').replace(/"[^"]+"/g,'').replace(/\\'/g,'').replace(/'[^']+'/g,'')

    joinMatches = clearedSQLString.match(new RegExp(@tableAlias + '(\\.[a-zA-Z_"][a-zA-Z0-9_"]*){2,}','g'));

    if not joinMatches or joinMatches.length is 0
      return sqlString

    leftJoin = (subkeys, parentEntity, path) =>
      as = subkeys.shift()
      relation = parentEntity.getRelationship(as)
      if not relation
        throw new Error('relation ' + parentEntity.name + '=>' + as + ' not found')
      inversedRelation = relation.inverseRelationship()
      subPath = path + "." + as
      unless ~alreadyJoined.indexOf(subPath)
        alreadyJoined.push(subPath)
        replaceNames[path] = path.replace(/\./g, "_")  unless replaceNames[path]
        replaceNames[subPath] = subPath.replace(/\./g, "_")  unless replaceNames[subPath]
        parentAlias = replaceNames[path]
        pathAlias = replaceNames[subPath]
        if relation.toMany and inversedRelation.toMany
          primaryRelation = @_relationshipByPriority(relation,inversedRelation)
          inversedRelation = relation.inverseRelationship()
          middleTableName = @_getMiddleTableNameForManyToManyRelation(primaryRelation)
          middleTableNameAlias = pathAlias + "__mid"
          if primaryRelation is relation
            query.left_join(middleTableName, middleTableNameAlias, parentAlias + "._id = " + middleTableNameAlias + ".reflexive")
            query.left_join(@_formatTableName(relation.destinationEntity.name), pathAlias, middleTableNameAlias + "." + relation.name + "_id = " + pathAlias + "._id")
          else
            query.left_join(middleTableName, middleTableNameAlias, parentAlias + "._id = " + middleTableNameAlias + "." + inversedRelation.name + "_id")
            query.left_join(@_formatTableName(relation.destinationEntity.name), pathAlias, middleTableNameAlias + ".reflexive" + " = " + pathAlias + "._id")
        else
          if relation.toMany
            query.left_join(@_formatTableName(relation.destinationEntity.name), pathAlias, pathAlias + "." + _.singularize(inversedRelation.name) + "_id" + " = " + parentAlias + "._id")
          else
            query.left_join(@_formatTableName(relation.destinationEntity.name), pathAlias, pathAlias + '._id' + ' = ' + parentAlias + '.' + relation.name + '_id')
      leftJoin(subkeys, relation.destinationEntity, subPath) if subkeys.length > 0

    replaceNames[@tableAlias] = @tableAlias
    for match in joinMatches
      match = match.slice(0, match.lastIndexOf("."))
      if match isnt @tableAlias
        replaceNames[match] = match.replace(/\./g, "_")
        match = match.replace(@tableAlias + ".", "")
        joins[match] = match

    alreadyJoined = []
    for key of joins
      _subkeys = key.split(".")
      #      console.log(key,_subkeys)
      leftJoin(_subkeys, request.entity, @tableAlias)
    replaceNameSorted = Object.keys(replaceNames).sort().reverse()

    sqlString = query.toString()
    for i of replaceNameSorted
      sqlString = sqlString.replace(new RegExp(replaceNameSorted[i].replace(".", "\\.") + "\\.(?![^\\s_]+\\\")", "g"), replaceNames[replaceNameSorted[i]] + ".")
      sqlString = sqlString.replace(new RegExp(replaceNameSorted[i].replace(".", "\\.") + @quoteSymbol, "g"), replaceNames[replaceNameSorted[i]] + @quoteSymbol)

    return sqlString

  processQuery:(query)->
    regString = query.replace(new RegExp('\'[^\']+\'','g'),'\'ignored\'')
    columnRegExp = new RegExp('SELF[\\w_]*(\\.[\\w_]+)+','gi')
    matches = regString.match(columnRegExp)
    if matches
      for match in matches
        column = match.replace(/\./g,'\.')
        columnAfter = match.replace(/\.([^\.]+)$/g,'.' + @quoteSymbol + '$1' + @quoteSymbol)
        query = query.replace(new RegExp(column,'g'),columnAfter)
    return query

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
            sql = 'INSERT INTO ' + @quoteSymbol + @_getMiddleTableNameForManyToManyRelation(relationship) + @quoteSymbol + ' (reflexive,' + @quoteSymbol + relationship.name + '_id' + @quoteSymbol + ') VALUES (' + @_recordIDForObjectID(object.objectID) + ',' + @_recordIDForObjectID(addedObject.objectID) + ')'
            sqls.push(sql)

        removedObjects = object._relationChanges?['removed_' + relationship.name]
        #        console.log(relationship.name,inversedRelationship.name,Object.keys(object.relationChanges),'added_' + relationship.name)
        if removedObjects
          for removedObject in removedObjects
#          console.log('xxxxx',object.relationChanges);
            sql = 'DELETE FROM ' + @quoteSymbol + @_getMiddleTableNameForManyToManyRelation(relationship) + @quoteSymbol + ' WHERE reflexive = ' + @_recordIDForObjectID(object.objectID) + ' AND ' + @quoteSymbol + relationship.name + '_id' + @quoteSymbol + ' = ' + @_recordIDForObjectID(removedObject.objectID)
            sqls.push(sql)
    async.forEachSeries sqls,(sql,cb)->
      transaction.query(sql,cb)
    ,callback

  _getMiddleTableNameForManyToManyRelation:(relationship)->
    inversedRelationship = relationship.inverseRelationship()
    reflexiveRelationship = @_relationshipByPriority(relationship,inversedRelationship);
    return @_formatTableName(reflexiveRelationship.entity.name) + '_' + reflexiveRelationship.name.toLowerCase()

  _valuesWithRelationshipsForObject:(object)->
    data = {}
    for key,value of object._changes
#      attribute = object.entity.getAttribute(key)
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

  permanentIDsForObjects:(objects) ->
    ids = []
    for object in objects
      ids.push(@_permanentIDForRecord(object.entity,@permanentIDsCache[object.objectID.toString()]))
    return ids

  newObjectID:(entity,referenceObject) ->
    new ManagedObjectID(@URL + '/' + entity.name + '/t' + referenceObject,entity)

  _permanentIDForRecord: (entity,referenceObject)->
    new ManagedObjectID(@URL + '/' + entity.name + '/p' + referenceObject,entity)

  _recordIDForObjectID: (objectID) ->
#    id = @permanentIDsCache[objectID.toString()]
#    if id
#      return id
#    console.log(@permanentIDsCache,objectID.toString())
    return objectID.recordId()
#    components = objectID.toString().split('/')
#    components[components.length - 1].replace(/^[pt]/,'')

  _relationshipByPriority: (relationship,inversedRelationship)->
    if relationship.name > inversedRelationship.name
      return relationship
    return inversedRelationship

  _formatTableName: (name)->
    return _.pluralize(name).toLowerCase()

  columnTypeForAttribute:(attribute)->
    type = null
    switch attribute.persistentType
      when 'bool','boolean'
        type = 'tinyint(1)'
      when 'string','email','url'
        type = 'varchar(' + (attribute.info.length or 255) + ')'
      when 'text'
        if attribute.info.length
          if attribute.info.length < 256
            type = 'tinytext'
          else if attribute.info.length < 65536
            type = 'text'
          else if attribute.info.length < 16777216
            type = 'mediumtext'
          else if attribute.info.length < 4294967296
            type = 'longtext'
        else
          type = 'longtext'
      when 'data'
        if attribute.info.length
          if attribute.info.length < 256
            type = 'tinyblob'
          else if attribute.info.length < 65536
            type = 'blob'
          else if attribute.info.length < 16777216
            type = 'mediumblob'
          else if attribute.info.length < 4294967296
            type = 'longblob'
        else
          type = 'longblob'
      when 'int','integer'
        type = 'int('+(attribute.info.length or 11)+')'
      when 'decimal'
        type = 'decimal('+(attribute.info.digits or 20)+','+(attribute.info.decimals or 5)+')'
      when 'float'
        type = 'float'
      when 'double'
        type = 'double'
      when 'date'
        type = 'datetime'
      when 'timestamp'
        type = 'bigint(20)'
      when 'uuid'
        type = 'char(36)'
      when 'transformable'
        type = 'mediumtext'
      when 'enum'
        return 'varchar(' + (attribute.info.length or 30) + ')'
      else return null
    return type

  _columnDefinitionForAttribute:(attribute)->
    type = @columnTypeForAttribute(attribute)
    if not type
      return null
    definition = @quoteSymbol + attribute.name + @quoteSymbol + ' '+type+' DEFAULT NULL'
    if attribute.info.unique
      definition += ' UNIQUE'
    return definition

  encodeValueForAttribute:(value,attribute)->
    if value is null
      return null
    switch attribute.persistentType
      when 'datetime','date'
        return moment(new Date(value)).format('YYYY-MM-DD HH:mm:ss')
    return value

  decodeValueForAttribute:(value,attribute)->
    if value is null
      return null
    switch attribute.persistentType
      when 'datetime','date'
        return new Date(value)
      when 'timestamp'
        return Number(value)
      when 'boolean'
        return !!value
    return value

  _indexesForEntity:(entity)->
    indexes = _.clone(entity.indexes)
    for attribute in entity.attributes
      if attribute.info.indexed
        indexes.push({name:attribute.name,columns:[attribute.name],type:'key'})
    return indexes





# schema synchronization
  syncSchema: (options,callback)->
    if typeof options is 'function'
      callback = options
      options = null
    options = options or {}

    objectModel = @storeCoordinator.objectModel

    @getCurrentVersion((err,currentVersion)=>
      if currentVersion is objectModel.version and not options.force
        callback()
      else if not currentVersion and not options.ignoreMissingVersion and not options.force
        callback(new Error('current version not found, rerun syncSchema with enabled option ignoreMissingVersion'))
      else if (not currentVersion and options.ignoreMissingVersion) or options.force
        try
          queries = @createSchemaQueries(options)
        catch err
          return callback(err)

        @_runRawQueriesInSingleTransaction(queries,callback)
      else
        migrations = objectModel.getMigrationsFrom(currentVersion)
        if not migrations or migrations.length is 0
          throw new Error('migration ' + currentVersion + '=>' + objectModel.version + ' not found')
        async.forEachSeries(migrations,@runMigration.bind(@),callback)
    )

  runMigration:(migration,callback)->
    objectModel = @storeCoordinator.objectModel
    async.forEachSeries(migration.scriptsBefore,(script,cb)=>
      @_runMigrationScript(migration.modelFrom,script,cb)
    ,(err)=>
#      console.log('err',err)
      return callback(err) if err
      try
        queries = @createMigrationQueries(migration)
        queries.push('UPDATE ' + @quoteSymbol + '_meta' + @quoteSymbol + ' SET ' + @quoteSymbol + 'value' + @quoteSymbol + ' = \'' + objectModel.version + '\' WHERE ' + @quoteSymbol + 'key' + @quoteSymbol + ' = \'version\'')
      catch err
        return callback(err)
      @_runRawQueriesInSingleTransaction(queries,(err)=>
        return callback(err) if err
        async.forEachSeries(migration.scriptsAfter,(script,cb)=>
          @_runMigrationScript(migration.modelTo,script,cb)
        ,callback)
      )
    )

  _runMigrationScript:(model,script,callback)->
    persistentStoreCoordinator = new PersistentStoreCoordinator(model,@storeCoordinator.globals)
    persistentStoreCoordinator.addStore(@)
    context = new ManagedObjectContext(persistentStoreCoordinator)
    try
      script.script(context,(err)=>
        if err
          context.destroy()
          return callback(err)
        context.saveAndDestroy(callback)
      )
    catch err
      callback(new Error('error running script on model ' + model.version + ', script name: \'' + (script.name or 'unknown') + '\', error: \'' + err.message + '\''))



  getCurrentVersion:(callback)->
    query = squel.select().from('_meta').field('value').where(@quoteSymbol + 'key' + @quoteSymbol + ' = ?','version').limit(1)
    @connectionPool.query(query.toString(),(err,rows)->
      return callback(err) if err
      callback(null,rows[0]?.value)
    )

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

  _runRawQueriesInSingleTransaction:(sqls,callback)->
    @connectionPool.createTransaction((err,transaction)=>
      return callback(err) if err
      async.forEachSeries(sqls,(sql,cb)=>
        transaction.query(sql,cb)
      ,(err)=>
        if err
          transaction.rollback(()=>
            if callback
              callback(err)
            @connectionPool.releaseTransaction(transaction)
          )
        else
          transaction.commit(()=>
            callback()
            @connectionPool.releaseTransaction(transaction)
          )
      )
    )


module.exports = GenericSQLStore