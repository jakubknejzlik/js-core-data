IncrementalStore = require('./../IncrementalStore')
PersistentStoreRequest = require('./../PersistentStoreRequest')
GenericPool = require('generic-pool')
async = require('async')
ManagedObjectID = require('./../../ManagedObjectID')
Predicate = require('./../../FetchClasses/Predicate')
FetchRequest = require('./../../FetchRequest')
SortDescriptor = require('./../../FetchClasses/SortDescriptor')
squel = require('squel')

#AttributeTransformer = require('../../Helpers/AttributeTransformer')

_ = require('underscore');
_.mixin(require('underscore.inflections'));


class GenericSQLStore extends IncrementalStore
  @::tableAlias = 'SELF'

  constructor: (@storeCoordinator,@URL,@globals)->
    if @storeCoordinator
      @connection = @createConnection()
#    @fetchedObjectValuesCache = {}
    @permanentIDsCache = {}

  createConnection: ()->
    throw new Error('createConnection must be overriden')

  execute:(request,context,callback,afterInsertCallback) ->
    if request not instanceof  PersistentStoreRequest
      throw new Error('request ' + request + ' is not instance of PersistentStoreRequest')

    if request.type is 'save'
      @connection.createTransaction (transaction)=>
        async.series [
          (seriesCallback)=> async.forEach request.insertedObjects,
            (insertedObject,cb)=>
              formattedTableName = @_formatTableName(insertedObject.entity.name)
#              inserts = ['`_id` = NULL']
#              for key,value of values
#                inserts.push('`' + key + '` = ' + mysql.escape(value))
              sql = 'INSERT INTO ' + formattedTableName + ' (`_id`) VALUES (?)'
              transaction.sendQuery(sql,[null],(err,result)=>
                if err
                  return cb(err)
                @permanentIDsCache[insertedObject.objectID.toString()] = result.insertId
                cb()
              )
            ,(err)=>
              afterInsertCallback();
              seriesCallback(err)
          (seriesCallback)=> async.forEach request.insertedObjects,
            (insertedObject,cb)=>
              [sql,updateValues] = @updateQueryForUpdatedObject(insertedObject)
              if sql
                transaction.sendQuery(sql,updateValues,(err,result)=>
                  if err
                    return cb(err)
                  @_updateRelationsForObject(transaction,insertedObject,cb)
                )
              else @_updateRelationsForObject(transaction,insertedObject,cb)
            ,seriesCallback
          (seriesCallback)=> async.forEach request.updatedObjects,
            (updatedObject,cb)=>
              [sql,updateValues] = @updateQueryForUpdatedObject(updatedObject)
              if sql
                transaction.sendQuery(sql,updateValues,(err)=>
                  if err
                    return cb(err)
                  @_updateRelationsForObject(transaction,updatedObject,cb)
                )
              else @_updateRelationsForObject(transaction,updatedObject,cb)
            ,(err)=>
              seriesCallback(err)
          (seriesCallback)=> async.forEach request.deletedObjects,
            (deletedObject,cb)=>
              formattedTableName = @_formatTableName(deletedObject.entity.name)
              id = @_recordIDForObjectID(deletedObject.objectID);
              sql = 'DELETE FROM `' + formattedTableName + '` WHERE `_id` = ' + id
              transaction.sendQuery sql,(err)->
                cb(err)
            ,(err)=>
              seriesCallback(err)
          ],(err)=>
            if err
              return transaction.rollback (rollbackError)=>
                @connection.releaseTransaction(transaction)
                callback(err)
            transaction.commit (err)=>
              @connection.releaseTransaction(transaction)
              callback(err)

    if request.type is 'fetch'
#      console.log('sql fetch',@_sqlForFetchRequest(request))
      @connection.sendRawQuery(@sqlForFetchRequest(request),(err,rows)=>
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
    @connection.sendRawQuery(@countSqlForFetchRequest(request),(err,result)=>
      callback(err,result[0].count)
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

      if attribute
        updates.push('`' + key + '` = ?')
        updateValues.push(attribute.encode(@encodeValueForAttribute(value,attribute)))
      else
        updates.push('`' + key + '` = ?')
        updateValues.push(value)
    if updates.length > 0
      return ['UPDATE `' + formattedTableName + '` SET ' + updates.join(',') + ' WHERE `_id` = ' + id,updateValues]
    else
      return [null,null]


  countSqlForFetchRequest:(request)->
    query = squel.select().from(@_formatTableName(request.entity.name),@tableAlias)
    query.field('COUNT(DISTINCT SELF._id)','count')
    if request.predicate
      query.where(request.predicate.toString())
    return @_getRawTranslatedQueryWithJoins(query,request)

  sqlForFetchRequest: (request) ->
    query = squel.select().from(@_formatTableName(request.entity.name),@tableAlias)

    if request.resultType is FetchRequest.RESULT_TYPE.MANAGED_OBJECTS
      query.group('SELF._id')
      query.field(@tableAlias + '.`_id`','_id')
      for attribute in request.entity.attributes
        query.field(@tableAlias + '.`' + attribute.name + '`',attribute.name)
      for relationship in request.entity.relationships
        if not relationship.toMany
          columnName = _.singularize(relationship.name) + '_id'
          query.field(@tableAlias + '.`' + columnName + '`',columnName)
    else
      if not request.fields
        query.field(@tableAlias + '.*')
      else
        for name,field of request.fields
          query.field(field,name)
      if request.group
        query.group(request.group)



    if request.predicate
      query.where(request.predicate.toString())

    query.limit(request.limit) if request.limit
    query.offset(request.offset) if request.offset

    if Array.isArray(request.sortDescriptors) and request.sortDescriptors.length > 0
      descriptors = request.sortDescriptors
      for descriptor in descriptors
        column = descriptor.attribute
        if column.indexOf(@tableAlias + '.') isnt 0
          column = @tableAlias + '.' + column
        query.order(column,descriptor.ascending)


    return @_getRawTranslatedQueryWithJoins(query,request)




  _getRawTranslatedQueryWithJoins:(query,request)->
    replaceNames = {}
    joins = {}

    sqlString = query.toString()

    clearedSQLString = sqlString.replace(/\\"/g,'').replace(/"[^"]+"/g,'').replace(/\\'/g,'').replace(/'[^']+'/g,'')
    joinMatches = clearedSQLString.match(new RegExp(@tableAlias + '(\\.[a-zA-Z_][a-zA-Z0-9_]*){2,}','g'));

    if not joinMatches or joinMatches.length is 0
      return sqlString

    leftJoin = (subkeys, parentEntity, path) =>
      as = subkeys.shift()
      relation = parentEntity.relationshipByName(as)
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
      sqlString = sqlString.replace(new RegExp(replaceNameSorted[i].replace(".", "\\.") + "`", "g"), replaceNames[replaceNameSorted[i]] + "`")

    return sqlString

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
            sql = 'INSERT INTO `' + @_getMiddleTableNameForManyToManyRelation(relationship) + '` (reflexive,`' + relationship.name + '_id`) VALUES (' + @_recordIDForObjectID(object.objectID) + ',' + @_recordIDForObjectID(addedObject.objectID) + ')'
            sqls.push(sql)

        removedObjects = object._relationChanges?['removed_' + relationship.name]
        #        console.log(relationship.name,inversedRelationship.name,Object.keys(object.relationChanges),'added_' + relationship.name)
        if removedObjects
          for removedObject in removedObjects
#          console.log('xxxxx',object.relationChanges);
            sql = 'DELETE FROM `' + @_getMiddleTableNameForManyToManyRelation(relationship) + '` WHERE reflexive = ' + @_recordIDForObjectID(object.objectID) + ' AND `' + relationship.name + '_id` = ' + @_recordIDForObjectID(removedObject.objectID)
            sqls.push(sql)
    async.forEachSeries sqls,(sql,cb)->
      transaction.sendQuery(sql,cb)
    ,callback

  _getMiddleTableNameForManyToManyRelation:(relationship)->
    return @_formatTableName(relationship.entity.name) + '_' + relationship.name

  _valuesWithRelationshipsForObject:(object)->
    data = {}
    for key,value of object._changes
      attribute = object.entity.getAttribute(key)
      data[key] = @decodeValueForAttribute(value,attribute);
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
    return objectID.recordId()
#    components = objectID.toString().split('/')
#    components[components.length - 1].replace(/^[pt]/,'')

  _relationshipByPriority: (relationship,inversedRelationship)->
    if relationship.name > inversedRelationship.name
      return relationship
    return inversedRelationship

  _formatTableName: (name)->
    return _.pluralize(name).toLowerCase()

  _formatManyToManyRelationshipTableName: (relationship)->
    inverseRelationship = relationship.inverseRelationship()
    reflexiveRelationship = @_relationshipByPriority(relationship,inverseRelationship)
    return @_formatTableName(reflexiveRelationship.entity.name) + '_' + reflexiveRelationship.name

  _columnDefinitionForAttribute:(attribute)->
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
      else return null
    definition = '`'+attribute.name+'` '+type+' DEFAULT NULL'
    if attribute.info.unique
      definition += ' UNIQUE'
    return definition

  encodeValueForAttribute:(value,attribute)->
    return value

  decodeValueForAttribute:(value,attribute)->
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
      if currentVersion is objectModel.version
        callback()
      else if not currentVersion and not options.ignoreVersion and not options.force
        callback(new Error('current version not found, rerun syncSchema with enabled option ignoreVersion'))
      else if (currentVersion isnt objectModel.version and options.ignoreVersion) or options.force
        try
          queries = @createSchemaQueries(options)
        catch err
          return callback(err)

        @_runRawQueriesInTransaction(queries,callback)
      else
        migration = objectModel.getMigrationFrom(currentVersion)
        if not migration
          throw new Error('migration ' + currentVersion + '=>' + objectModel.version + ' not found')
        try
          queries = @createMigrationQueries(migration)
        catch err
          return callback(err)

        @_runRawQueriesInTransaction(queries,callback)
    )


  getCurrentVersion:(callback)->
    query = squel.select().from('_meta').field('value').where('`key` = ?','version').limit(1)
    @connection.sendRawQuery(query.toString(),(err,rows)->
      return callback(err) if err
      callback(null,rows[0]?.value)
    )

  _runRawQueriesInTransaction:(sqls,callback)->
    @connection.createTransaction((transaction)=>
      async.forEachSeries(sqls,(sql,cb)=>
        transaction.sendQuery(sql,cb)
      ,(err)=>
        if err
          transaction.rollback(()=>
            if callback
              callback(err)
            @connection.releaseTransaction(transaction)
          )
        else
          transaction.commit(()=>
            callback()
            @connection.releaseTransaction(transaction)
          )
      )
    )



module.exports = GenericSQLStore