#GenericPool = require('generic-pool')
url = require('url')
async = require('async')
squel = require('squel')
moment = require('moment')
Promise = require('bluebird')

IncrementalStore = require('./../IncrementalStore')
PersistentStoreRequest = require('./../PersistentStoreRequest')
ManagedObjectID = require('./../../ManagedObjectID')
Predicate = require('./../../FetchClasses/Predicate')
FetchRequest = require('./../../FetchRequest')
SortDescriptor = require('./../../FetchClasses/SortDescriptor')

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

    parsedUrl = url.parse(@URL)
    @schemaName = parsedUrl.pathname.substring(1)
    @auth = parsedUrl.auth

    if @storeCoordinator
      @connectionPool = new SQLConnectionPool(@URL,(url)=>
        return @createConnection(url)
      ,@,@globals)
    #      @connection = @createConnection()
    #    @fetchedObjectValuesCache = {}
    @permanentIDsCache = {}

  createConnection: (url)->
    throw new Error('createConnection must be overriden')

  closeAllConnections: (callback)->
    @connectionPool.closeAllConnections(callback)

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
          (seriesCallback)=>
            async.forEachSeries(request.insertedObjects,(insertedObject,cb)=>
              [sql,updateValues] = @updateQueryForUpdatedObject(insertedObject)
              if sql
                transaction.query(sql,updateValues,cb)
              else cb()
            ,seriesCallback)
          (seriesCallback)=> async.forEachSeries request.insertedObjects,
            (insertedObject,cb)=>
              @_updateRelationsForObject(transaction,insertedObject,cb)
          ,seriesCallback
          (seriesCallback)=> async.forEachSeries request.updatedObjects,
            (updatedObject,cb)=>
              [sql,updateValues] = @updateQueryForUpdatedObject(updatedObject)
              if sql
                transaction.query(sql,updateValues,cb)
              else cb()
          ,seriesCallback
          (seriesCallback)=> async.forEachSeries request.updatedObjects,
            (updatedObject,cb)=>
              @_updateRelationsForObject(transaction,updatedObject,cb)
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
          for attribute in request.entity.getNonTransientAttributes()
            _row[attribute.name] = row[attribute.name]
          for relationship in request.entity.relationships
            if not relationship.toMany
              columnName = _.singularize(relationship.name) + '_id'
              _row[columnName] = row[columnName]
          objectID = @_permanentIDForRecord(request.entity,row._id)
          #          @fetchedObjectValuesCache[objectID.toString()] = _row;
          for attribute in request.entity.getNonTransientAttributes()
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


  processRequest:(request)->
    if not request.fields
      fields = {}
      for attribute in request.entity.getNonTransientAttributes()
        fields[attribute.name] = @tableAlias + '.' + attribute.name
      request.fields = fields
      request.fields['_id'] = @tableAlias + '._id'
    else
      allFieldsMark = null
      for name,field of request.fields
        if field in ['SELF.*','*']
          allFieldsMark = name
          break
      if allFieldsMark
        delete request.fields[allFieldsMark]
        for attribute in request.entity.getNonTransientAttributes()
          request.fields[attribute.name] = @tableAlias + '.' + attribute.name
        request.fields['_id'] = @tableAlias + '._id'

    if request.type isnt 'fetch'
      request.fields['_id'] = @tableAlias + '._id'


  countSqlForFetchRequest:(request)->
    @processRequest(request)
    query = squel.select({autoQuoteAliasNames:no}).from(@_formatTableName(request.entity.name),@tableAlias)
    query.field('COUNT(DISTINCT ' + @tableAlias + '._id)','count')
    if request.predicate
      query.where(@parsePredicate(request.predicate),request)
    if request.havingPredicate
      query.having(@parsePredicate(request.havingPredicate,request))

    if request.group
      query.group(request.group)

    sqlString = @_getRawTranslatedQueryWithJoins(query,request)
    return @processQuery(sqlString,request)

  sqlForFetchRequest: (request) ->
    query = squel.select({autoQuoteAliasNames:no}).from(@_formatTableName(request.entity.name),@tableAlias)

    if request.resultType is FetchRequest.RESULT_TYPE.MANAGED_OBJECTS
      query.group(@tableAlias + '._id')
      query.field(@tableAlias + '.' + @quoteSymbol + '_id' + @quoteSymbol,@quoteSymbol + '_id' + @quoteSymbol)
      for attribute in request.entity.getNonTransientAttributes()
        query.field(@tableAlias + '.' + @quoteSymbol + attribute.name + @quoteSymbol,@quoteSymbol + attribute.name + @quoteSymbol)
      for relationship in request.entity.relationships
        if not relationship.toMany
          columnName = _.singularize(relationship.name) + '_id'
          query.field(@tableAlias + '.' + @quoteSymbol + columnName + @quoteSymbol,@quoteSymbol + columnName + @quoteSymbol)
    else
      @processRequest(request)


      for name,field of request.fields
        query.field(field,@quoteSymbol + name + @quoteSymbol)

      if request.group
        query.group(request.group)

    if request.predicate
      query.where(@parsePredicate(request.predicate,request))
    if request.havingPredicate
      query.having(@parsePredicate(request.havingPredicate,request))

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
    return @processQuery(sqlString,request)


  parsePredicate:(predicate,request)->
    string = predicate.toString()
    return string

  _getRawTranslatedQueryWithJoins:(query,request)->
    replaceNames = {}
    joins = {}

    sqlString = query.toString()

    if request?.fields
      for fieldName,fieldValue of request.fields
        if fieldValue.indexOf(@tableAlias + '.' + fieldName) is -1
          sqlString = sqlString.replace(new RegExp(@tableAlias + '.' + fieldName,'g'),fieldValue)

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
            query.left_join(@quoteSymbol + middleTableName + @quoteSymbol, middleTableNameAlias, parentAlias + "._id = " + middleTableNameAlias + ".reflexive")
            query.left_join(@quoteSymbol + @_formatTableName(relation.destinationEntity.name) + @quoteSymbol, pathAlias, middleTableNameAlias + "." + relation.name + "_id = " + pathAlias + "._id")
          else
            query.left_join(@quoteSymbol + middleTableName + @quoteSymbol, middleTableNameAlias, parentAlias + "._id = " + middleTableNameAlias + "." + inversedRelation.name + "_id")
            query.left_join(@quoteSymbol + @_formatTableName(relation.destinationEntity.name) + @quoteSymbol, pathAlias, middleTableNameAlias + ".reflexive" + " = " + pathAlias + "._id")
        else
          if relation.toMany
            query.left_join(@quoteSymbol + @_formatTableName(relation.destinationEntity.name) + @quoteSymbol, pathAlias, pathAlias + "." + _.singularize(inversedRelation.name) + "_id" + " = " + parentAlias + "._id")
          else
            query.left_join(@quoteSymbol + @_formatTableName(relation.destinationEntity.name) + @quoteSymbol, pathAlias, pathAlias + '._id' + ' = ' + parentAlias + '.' + relation.name + '_id')
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

    if request?.fields
      for fieldName,fieldValue of request.fields
        if fieldValue.indexOf(@tableAlias + '.' + fieldName) is -1
          sqlString = sqlString.replace(new RegExp(@tableAlias + '.' + fieldName,'g'),fieldValue)

    for i of replaceNameSorted
      sqlString = sqlString.replace(new RegExp(replaceNameSorted[i].replace(".", "\\.") + "\\.(?![^\\s_]+\\\")", "g"), replaceNames[replaceNameSorted[i]] + ".")
      sqlString = sqlString.replace(new RegExp(replaceNameSorted[i].replace(".", "\\.") + @quoteSymbol, "g"), replaceNames[replaceNameSorted[i]] + @quoteSymbol)

    return sqlString

  processQuery:(query,request)->

    regString = query.replace(new RegExp('\'[^\']+\'','g'),'\'ignored\'')

    columnRegExp = new RegExp(@tableAlias + '[\\w_]*(\\.[\\w_]+)+','gi')
    matches = regString.match(columnRegExp)
    matches = _.unique(matches)
    matches.sort().reverse()
    if matches
      for match in matches
        column = match.replace(/\./g,'\.')
        columnAfter = match.replace(/\.([^\.]+)$/g,'.' + @quoteSymbol + '$1' + @quoteSymbol)
        query = query.replace(new RegExp(column,'g'),columnAfter)

    tableName = @_formatTableName(request.entity.name)
    query = query.replace("FROM #{tableName} #{@tableAlias}","FROM #{@quoteSymbol}#{tableName}#{@quoteSymbol} #{@tableAlias}")

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
            sqls.push(@_insertQueryForManyToMany(relationship,object,addedObject))

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

  _insertQueryForManyToMany:(relationship,object,addedObject) ->
    return 'INSERT INTO ' + @quoteSymbol + @_getMiddleTableNameForManyToManyRelation(relationship) + @quoteSymbol + ' (reflexive,' + @quoteSymbol + relationship.name + '_id' + @quoteSymbol + ') VALUES (' + @_recordIDForObjectID(object.objectID) + ',' + @_recordIDForObjectID(addedObject.objectID) + ')'


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
      when 'bigint'
        type = 'bigint('+(attribute.info.length or 20)+')'
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
        return moment.utc(value).toISOString()#.format('YYYY-MM-DD HH:mm:ss')
    return value

  decodeValueForAttribute:(value,attribute)->
    if value is null
      return null
    switch attribute.persistentType
      when 'datetime','date'
        return moment.utc(value).toDate()
      when 'timestamp'
        return Number(value)
      when 'boolean'
        return !!value
    return value

  _indexesForEntity:(entity)->
    indexes = _.clone(entity.indexes)
    for attribute in entity.getNonTransientAttributes()
      if attribute.info.indexed
        indexes.push({name:attribute.name,columns:[attribute.name],type:'key'})
    return indexes





# schema synchronization
  syncSchema: (options)->
    return new Promise((resolve, reject) =>
      @connectionPool.createTransaction((err,transaction)=>
        return reject(err) if err
        @createSchemaQueries(options,transaction,(err,queries)=>
          if err
            transaction.rollback(()=>
              reject(err)
            )
          else
            @_runRawQueriesInSingleTransaction(queries,transaction,(err, result) =>
              return reject(err) if err
              resolve(result)
            )
        )
      )
    )


  runMigration:(migration)->
    return new Promise((resolve, reject) =>
      objectModel = @storeCoordinator.objectModel
      async.forEachSeries(migration.scriptsBefore,(script,cb)=>
        @_runMigrationScript(migration.modelFrom,script,cb)
      ,(err)=>
        return reject(err) if err
        try
          queries = @createMigrationQueries(migration)
          queries.push('UPDATE ' + @quoteSymbol + '_meta' + @quoteSymbol + ' SET ' + @quoteSymbol + 'value' + @quoteSymbol + ' = \'' + objectModel.version + '\' WHERE ' + @quoteSymbol + 'key' + @quoteSymbol + ' = \'version\'')
        catch err
          return reject(err)
        @_runRawQueriesInSingleTransaction(queries,(err)=>
          return reject(err) if err
          async.forEachSeries(migration.scriptsAfter,(script,cb)=>
            @_runMigrationScript(migration.modelTo,script,cb)
          ,(err,result) =>
            return reject(err) if err
            resolve(result)
          )
        )
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



  getCurrentVersion:()->
    return new Promise((resolve, reject) =>
      query = squel.select().from('_meta').field('value').where(@quoteSymbol + 'key' + @quoteSymbol + ' = ?','version').limit(1)
      @connectionPool.query(query.toString(),(err,rows)->
#        return reject(err) if err
        return resolve(null) if not rows
        resolve(rows[0]?.value)
      )
    )

  createMigrationQueries:(migration)->
    sqls = []
    changedRelationshipsSqls = []
    entityChangedNames = {}
    addedEntitiesNames = []
    modelTo = migration.modelTo
    modelFrom = migration.modelFrom

    for change in migration.entitiesChanges
      entityName = change.entity
      switch change.change
        when '+'
          addedEntitiesNames.push(entityName)
          sqls = sqls.concat(@createEntityQueries(modelTo.getEntity(entityName),no,{noRelationships: yes}))
          for relationship in modelTo.getEntity(entityName).relationships
            inverseRelationship = relationship.inverseRelationship()
            if not relationship.toMany
              changedRelationshipsSqls = changedRelationshipsSqls.concat(@_addRelationshipQueries(relationship.entity.name,relationship))
            if not inverseRelationship.toMany
              changedRelationshipsSqls = changedRelationshipsSqls.concat(@_addRelationshipQueries(inverseRelationship.entity.name,inverseRelationship))
        when '-'
          entity = modelFrom.getEntity(entityName)
          for name,relationship of entity.relationshipsByName()
            sqls.push(@_removeRelationshipQuery(entityName,relationship))
          sqls = sqls.concat(@_dropEntityQueries(modelFrom.getEntity(entityName)))
        else
          entityChangedNames[change.change] = entityName
          sqls.push('ALTER TABLE ' + @quoteSymbol + @_formatTableName(entityName) + @quoteSymbol + ' RENAME TO ' + @quoteSymbol + @_formatTableName(change.change) + @quoteSymbol)

    for change in migration.entitiesChanges
      entityName = change.entity
      switch change.change
        when '+'
          for relationship in modelTo.getEntity(entityName).relationships
            inverseRelationship = relationship.inverseRelationship()
            if relationship.toMany and inverseRelationship.toMany
              sqls = sqls.concat(@createRelationshipQueries(relationship))

    updatedEntities = _.uniq(Object.keys(migration.attributesChanges).concat(Object.keys(migration.relationshipsChanges)))

    for entityName in updatedEntities
      entityTo = modelTo.getEntity(entityName) or modelTo.getEntity(entityChangedNames[entityName])
      entityFrom = modelFrom.getEntity(entityName) or modelFrom.getEntity(entityChangedNames[entityName])

      if entityFrom
        for attribute in entityFrom.getNonTransientAttributes()
          change = migration.attributesChanges[entityName]?[attribute.name]
          if change
            switch change
              when '+'
                break
              when '-'
                sqls.push(@_removeColumnQuery(entityName,attribute.name))
                break
              else
                try
                  newAttribute = entityTo.getAttribute(change)
                  sqls.push(@_renameAttributeQuery(@_formatTableName(entityName),attribute,newAttribute))
                catch e
                  throw new Error('attribute ' + entityTo.name + '->' + change + ' not found in version ' + modelFrom.version)

      if entityTo and entityName not in addedEntitiesNames
        for attribute in entityTo.getNonTransientAttributes()
          change = migration.attributesChanges[entityName]?[attribute.name]
          if change is '+'
            sqls.push('ALTER TABLE ' + @quoteSymbol + @_formatTableName(entityName) + @quoteSymbol + ' ADD COLUMN ' + @_columnDefinitionForAttribute(attribute))



      # relationships oneToMany
      if entityFrom
        for relationship in entityFrom.relationships
          if not relationship.toMany
            change = migration.relationshipsChanges[entityName]?[relationship.name]
            if change and change not in ['+','-']
              try
                newRelationship = entityTo.getRelationship(change)
                sqls.push(@_renameRelationshipQuery(@_formatTableName(entityName),relationship,newRelationship))
#                    sqls.push('ALTER TABLE ' + @quoteSymbol + @_formatTableName(entityName) + @quoteSymbol + ' RENAME COLUMN ' + @quoteSymbol +  + @quoteSymbol + ' TO ' + @quoteSymbol + newRelationship.name + '_id' + @quoteSymbol)
              catch e
                throw new Error('relationship ' + entityTo.name + '->' + change + ' not found in version ' + modelTo.version)


      # relationships manyToMany
      if entityFrom
        for relationship in entityFrom.relationships
          inverseRelationship = relationship.inverseRelationship()
          reflexiveRelationship = @_relationshipByPriority(relationship,inverseRelationship)
          reflexiveTableName = @_formatTableName(reflexiveRelationship.entity.name) + '_' + reflexiveRelationship.name
          if relationship.toMany and inverseRelationship.toMany
            change = migration.relationshipsChanges[entityName]?[relationship.name] or migration.relationshipsChanges[inverseRelationship.entity.name]?[inverseRelationship.name]
            if change
              switch change
                when '+'
                  break
#              sqls = sqls.concat(@createEntityRelationshipQueries(entityTo))
                when '-'
                  sqls.push(@_dropTableQuery(reflexiveTableName))

        for relationship in entityFrom.relationships
          inverseRelationship = relationship.inverseRelationship()
          reflexiveRelationship = @_relationshipByPriority(relationship,inverseRelationship)
          reflexiveTableName = @_formatTableName(reflexiveRelationship.entity.name) + '_' + reflexiveRelationship.name
          if relationship.toMany and inverseRelationship.toMany
            change = migration.relationshipsChanges[entityName]?[relationship.name]
            if change and change not in ['+','-']
              newRelationship = entityTo.getRelationship(change)
              newInverseRelationship = newRelationship.inverseRelationship()
              newReflexiveRelationship = @_relationshipByPriority(newRelationship,newInverseRelationship)
              reflexiveRelationship = @_relationshipByPriority(relationship,inverseRelationship)
              reflexiveTableName = @quoteSymbol + @_formatTableName(reflexiveRelationship.entity.name) + '_' + reflexiveRelationship.name + @quoteSymbol
              newReflexiveTableName = @quoteSymbol + @_formatTableName(newReflexiveRelationship.entity.name) + '_' + newReflexiveRelationship.name + @quoteSymbol
              sqls.push('ALTER TABLE ' + reflexiveTableName + ' RENAME TO ' + newReflexiveTableName)

    for entityName,entityFrom of modelFrom.entities
      for relationship in entityFrom.relationships
        inverseRelationship = relationship.inverseRelationship()
        if not relationship.toMany
          change = migration.relationshipsChanges[entityName]?[relationship.name] or migration.relationshipsChanges[inverseRelationship.entity.name]?[inverseRelationship.name]
          if change
            switch change
              when '+'
                break
              when '-'
                sqls.push(@_removeRelationshipQuery(relationship.entity.name,relationship))

    for entityName,entityTo of modelTo.entities
      if entityTo and entityTo.name not in addedEntitiesNames
        for relationship in entityTo.relationships
          inverseRelationship = relationship.inverseRelationship()
          if not relationship.toMany
            change = migration.relationshipsChanges[entityName]?[relationship.name] or migration.relationshipsChanges[inverseRelationship.entity.name]?[inverseRelationship.name]
            #            if relationship.toMany
            #              relationship = inverseRelationship
            switch change
              when '+'
                changedRelationshipsSqls = changedRelationshipsSqls.concat(@_addRelationshipQueries(relationship.entity.name,relationship))
                break
      for relationship in entityTo.relationships
        inverseRelationship = relationship.inverseRelationship()
        if relationship.toMany and inverseRelationship.toMany
          change = migration.relationshipsChanges[entityName]?[relationship.name] or migration.relationshipsChanges[inverseRelationship.entity.name]?[inverseRelationship.name]
          if change is '+'
            changedRelationshipsSqls = changedRelationshipsSqls.concat(@createRelationshipQueries(relationship))

    sqls = sqls.concat(changedRelationshipsSqls)
    return _.uniq(sqls)

  _dropTableQuery:(tableName)->
    return 'DROP TABLE IF EXISTS ' + @quoteSymbol + tableName + @quoteSymbol
  _dropEntityQueries:(entity)->
    return [@_dropTableQuery(@_formatTableName(entity.name))]
  _renameRelationshipQuery:(tableName,relationshipFrom,relationshipTo)->
    return 'ALTER TABLE ' + @quoteSymbol + tableName + @quoteSymbol + ' RENAME COLUMN ' + @quoteSymbol + relationshipFrom.name + '_id' + @quoteSymbol + ' TO ' + @quoteSymbol + relationshipTo.name + '_id' + @quoteSymbol
  _renameAttributeQuery:(tableName,attributeFrom,attributeTo)->
    return 'ALTER TABLE ' + @quoteSymbol + tableName + @quoteSymbol + ' RENAME COLUMN ' + @quoteSymbol + attributeFrom.name + @quoteSymbol + ' TO ' + @quoteSymbol + attributeTo.name + @quoteSymbol
  _removeColumnQuery:(entityName,column)->
    'ALTER TABLE ' + @quoteSymbol + @_formatTableName(entityName) + @quoteSymbol + ' DROP COLUMN ' + @quoteSymbol + column + @quoteSymbol
  _removeRelationshipQuery:(entityName,relationship)->
    inverseRelationship = relationship.inverseRelationship()
    if relationship.toMany and inverseRelationship.toMany
      reflexiveRelationship = @_relationshipByPriority(relationship,inverseRelationship)
      reflexiveTableName = @_formatTableName(reflexiveRelationship.entity.name) + '_' + reflexiveRelationship.name
      return @_dropTableQuery(reflexiveTableName)
    else
      return @_removeColumnQuery(entityName,relationship.name + '_id')
  _addRelationshipQueries:(entityName,relationship)->
    return ['ALTER TABLE ' + @quoteSymbol + @_formatTableName(entityName) + @quoteSymbol + ' ADD COLUMN ' + @_relationshipColumnDefinition(relationship)]

  createEntityRelationshipQueries:(entity,force)->
    sqls = []
    for key,relationship of entity.relationships
      sqls = sqls.concat(@createRelationshipQueries(relationship,force))
    return sqls

  createRelationshipQueries:(relationship,force)->
    sqls = []
    if relationship.toMany
      inverseRelationship = relationship.inverseRelationship()
      if inverseRelationship.toMany
        reflexiveRelationship = @_relationshipByPriority(relationship,inverseRelationship)
        reflexiveTableName = @_getMiddleTableNameForManyToManyRelation(reflexiveRelationship)
        sqls.push('CREATE TABLE IF NOT EXISTS `' + reflexiveTableName + '` (`'+reflexiveRelationship.name+'_id` int(11) NOT NULL,`reflexive` int(11) NOT NULL, PRIMARY KEY (`'+reflexiveRelationship.name+'_id`,`reflexive`))')
    return sqls
  _relationshipColumnDefinition:(relationship)->
    return @quoteSymbol + relationship.name+'_id' + @quoteSymbol + ' int(11) DEFAULT NULL'


  _runRawQueriesInSingleTransaction:(sqls,transaction,callback)->
    if typeof transaction is 'function'
      callback = transaction
      transaction = undefined
    run = (transaction)=>
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

    if transaction
      return run(transaction)
    @connectionPool.createTransaction((err,transaction)=>
      return callback(err) if err
      run(transaction)
    )


module.exports = GenericSQLStore
