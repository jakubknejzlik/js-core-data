IncrementalStore = require('./../IncrementalStore')
PersistentStoreRequest = require('./../PersistentStoreRequest')
GenericPool = require('generic-pool')
async = require('async')
ManagedObjectID = require('./../../ManagedObjectID')
Predicate = require('./../../FetchClasses/Predicate')
squel = require('squel')

AttributeTransformer = require('../../Helpers/AttributeTransformer')

_ = require('underscore');
_.mixin(require('underscore.inflections'));


class GenericSQLStore extends IncrementalStore
  @::tableAlias = 'SELF'

  constructor: (@storeCoordinator,@URL,@globals)->
    if @storeCoordinator
      @connection = @createConnection()
    @fetchedObjectValuesCache = {}
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
        for row in rows
          _row = {}
          for attribute in request.entity.attributes
            _row[attribute.name] = row[attribute.name]
          objectID = @_permanentIDForRecord(request.entity,row._id)
          @fetchedObjectValuesCache[objectID.toString()] = _row;
          ids.push(objectID)
        callback(null,ids)
      )

  updateQueryForUpdatedObject:(updatedObject)->
    formattedTableName = @_formatTableName(updatedObject.entity.name)
    id = @_recordIDForObjectID(updatedObject.objectID);
    values = @_valuesWithRelationshipsForObject(updatedObject)
    updates = []
    updateValues = []
    for key,value of values
      updates.push('`' + key + '` = ?')
      updateValues.push(value)
    if updates.length > 0
      return ['UPDATE `' + formattedTableName + '` SET ' + updates.join(',') + ' WHERE `_id` = ' + id,updateValues]
    else
      return [null,null]


  sqlForFetchRequest: (request) ->
    query = squel.select().from(@_formatTableName(request.entity.name),@tableAlias).field(@tableAlias + '._id','_id')
    for attribute in request.entity.attributes
      query.field(@tableAlias + '.' + attribute.name,attribute.name)
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

    query.group('SELF._id')

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
      data[key] = AttributeTransformer.persistentValueForAttribute(value,object.entity.attributesByName()[key]);
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
        sql = 'SELECT ' + columns.join(',') + ' FROM `' + @_formatTableName(relationship.destinationEntity.name) + '` WHERE `_id` IN (SELECT `' + relationship.name + '_id` FROM `' + @_formatTableName(relationship.entity.name) + '_' + relationship.name + '` WHERE `reflexive` = ' + @_recordIDForObjectID(ObjectID) + ')'
      else
        sql = 'SELECT ' + columns.join(',') + ' FROM `' + @_formatTableName(relationship.destinationEntity.name) + '` WHERE `_id` IN (SELECT `reflexive` FROM `' + @_formatTableName(inversedRelationship.entity.name) + '_' + inversedRelationship.name + '` WHERE `' + inversedRelationship.name + '_id` = ' + @_recordIDForObjectID(ObjectID) + ')'
#      console.log('sql!!??',relationship.name,sql)
    else
#      if mainRelationship is relationship
        if inversedRelationship.toMany
          sql = 'SELECT ' + columns.join(',') + ' FROM `' + @_formatTableName(relationship.destinationEntity.name) + '` WHERE `_id` IN (SELECT `' + relationship.name + '_id` FROM `' + @_formatTableName(relationship.entity.name) + '` WHERE `_id` = ' + @_recordIDForObjectID(ObjectID) + ') LIMIT 1'
        else
          sql = 'SELECT ' + columns.join(',') + ' FROM `' + @_formatTableName(relationship.destinationEntity.name) + '` WHERE `' + inversedRelationship.name + '_id` = ' + @_recordIDForObjectID(ObjectID)
#      else
#        if relationship.toMany
#          sql = 'SELECT ' + columns.join(',') + ' FROM `' + @_formatTablxeName(relationship.destinationEntity.name) + '` WHERE `' + inversedRelationship.name + '_id` = ' + mysql.escape(@_recordIDForObjectID(ObjectID))
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


  syncSchema: (options,callback)->
    throw new Error('createConnection must be overriden')

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
      definition += ' UNIQUE'
    return definition


module.exports = GenericSQLStore