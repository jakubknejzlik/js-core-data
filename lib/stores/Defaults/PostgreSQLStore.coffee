GenericSQLStore = require('./GenericSQLStore')
PersistentStoreRequest = require('./../PersistentStoreRequest')
GenericPool = require('generic-pool')
async = require('async')
ManagedObjectID = require('./../../ManagedObjectID')
Predicate = require('./../../FetchClasses/Predicate')

SQLConnection = require('./SQLConnection')
SQLTransaction = require('./SQLTransaction')

process.env.NODE_ENV = 'production'

try
  require('pg')
catch e
  throw new Error('pg module is required to use SQLite storage, please install it by running npm install --save pg')

pg = require('pg')

if process.env.NODE_ENV is 'production'
  try
    require('pg-native')
    pg = require('pg').native
  catch e
    console.log('pg-native is recommended for running in production environment, you install module by running  npm install --save pg-native')

_ = require('underscore');
_.mixin(require('underscore.inflections'));


class PostgreSQLStore extends GenericSQLStore

  createConnection:()->
    return new PostgreSQLConnection(@URL,this)

  createSchemaQueries: (options = {},transaction,callback)->
    objectModel = @storeCoordinator.objectModel
    sqls = []
    transaction.query('SELECT table_name FROM information_schema.tables WHERE table_schema = \'public\' ORDER BY table_name',(err,rows)=>
      return callback(err) if err
      for row in rows
        sqls.push(@_dropTableQuery(row['table_name']))

      try
        for key,entity of objectModel.entities
          sqls = sqls.concat(@createEntityQueries(entity,options.force))

        for key,entity of objectModel.entities
          sqls = sqls.concat(@createEntityRelationshipQueries(entity,options.force))

        for key,entity of objectModel.entities
          for relationship in entity.relationships
            if not relationship.toMany
              sqls.push('ALTER TABLE "' + @_formatTableName(entity.name) + '" ADD CONSTRAINT "fk_' + @_formatTableName(entity.name) + '_' + relationship.name + '_id" FOREIGN KEY ("' + relationship.name + '_id")  REFERENCES "' + @_formatTableName(relationship.destinationEntity.name) + '"("_id") ON DELETE ' + relationship.getOnDeleteRule())

        sqls.push('CREATE TABLE IF NOT EXISTS "_meta" ("key" varchar(10) NOT NULL,"value" varchar(250) NOT NULL,PRIMARY KEY ("key"))')
        sqls.push('DELETE FROM "_meta" WHERE ' + @quoteSymbol + 'key' + @quoteSymbol + ' = \'version\'')
        sqls.push('INSERT INTO "_meta" VALUES(\'version\',\'' + objectModel.version + '\')')

        callback(null,sqls)
      catch err
        callback(err)
    )

  createEntityQueries:(entity,force = no,options = {})->
    sqls = []
    tableName = @_formatTableName(entity.name)
    parts = ['"_id" SERIAL PRIMARY KEY']


    for attribute in entity.getNonTransientAttributes()
      columnDefinition = @_columnDefinitionForAttribute(attribute)
      if columnDefinition
        parts.push(columnDefinition);
      else
        throw new Error('unknown attribute type ' + attribute.type)

    if not options.noRelationships
      for relationship in entity.relationships
        if not relationship.toMany
          parts.push(@_relationshipColumnDefinition(relationship))

#    if force
#      sqls.push('DROP TABLE IF EXISTS "' + tableName + '" CASCADE')
    sql = 'CREATE TABLE IF NOT EXISTS "' + tableName + '" ('
    sql += parts.join(',')
    sql += ')'

    for index in @_indexesForEntity(entity)
      sql +=';CREATE ' + (if index.type is 'unique' then 'UNIQUE' else '') + ' INDEX "'+ tableName + '_' + index.name+'" ON "'+tableName+'" ("'+index.columns.join('","')+'")'

    sqls.push(sql)

    #    if not options.ignoreRelationships
    #      sqls = sqls.concat(@createEntityRelationshipQueries(entity,force))

    return sqls



  _dropTableQuery:(tableName)->
    return 'DROP TABLE IF EXISTS ' + @quoteSymbol + tableName + @quoteSymbol + ' CASCADE'
  _relationshipColumnDefinition:(relationship)->
    return '"'+relationship.name+'_id" int DEFAULT NULL'

  _insertQueryForManyToMany:(relationship,object,addedObject) ->
    tableName = @_getMiddleTableNameForManyToManyRelation(relationship)
    return 'INSERT INTO "' + tableName + '" ("reflexive","' + relationship.name + '_id") SELECT ' + @_recordIDForObjectID(object.objectID) + ',' + @_recordIDForObjectID(addedObject.objectID) + ' WHERE NOT EXISTS (SELECT 1 FROM "' + tableName + '" WHERE "reflexive" = ' + @_recordIDForObjectID(object.objectID) + ' AND "' + relationship.name + '_id" = ' + @_recordIDForObjectID(addedObject.objectID) + ')'
  _addRelationshipQueries:(entityName,relationship)->
    return [
      'ALTER TABLE ' + @quoteSymbol + @_formatTableName(entityName) + @quoteSymbol + ' ADD COLUMN ' + @_relationshipColumnDefinition(relationship),
      'ALTER TABLE "' + @_formatTableName(entityName) + '" ADD CONSTRAINT "fk_' + @_formatTableName(entityName) + '_' + relationship.name + '_id" FOREIGN KEY ("' + relationship.name + '_id")  REFERENCES "' + @_formatTableName(relationship.destinationEntity.name) + '"("_id") ON DELETE ' + relationship.getOnDeleteRule()
    ]


#  createRelationshipQueries:(relationship,force)->
#    sqls = []
#    if relationship.toMany
#      inversedRelationship = relationship.inverseRelationship()
#      if inversedRelationship.toMany
#        reflexiveRelationship = @_relationshipByPriority(relationship,inversedRelationship)
#        reflexiveTableName = @_getMiddleTableNameForManyToManyRelation(reflexiveRelationship)
#        if force
#          sqls.push('DROP TABLE IF EXISTS "' + reflexiveTableName  + '" CASCADE')
#        sqls.push('CREATE TABLE IF NOT EXISTS "' + reflexiveTableName + '" ("'+reflexiveRelationship.name+'_id" serial NOT NULL,"reflexive" serial NOT NULL, PRIMARY KEY ("'+reflexiveRelationship.name+'_id","reflexive"))')
#    return sqls
  createRelationshipQueries:(relationship,force)->
    sqls = []
    if relationship.toMany
      inversedRelationship = relationship.inverseRelationship()
      if inversedRelationship.toMany
        reflexiveRelationship = @_relationshipByPriority(relationship,inversedRelationship)
        reflexiveTableName = @_getMiddleTableNameForManyToManyRelation(reflexiveRelationship)
#        if force
#          sqls.push('DROP TABLE IF EXISTS "' + reflexiveTableName  + '" CASCADE')

        parts = []

        parts.push('"'+reflexiveRelationship.name+'_id" serial NOT NULL')
        parts.push('"reflexive" serial NOT NULL')
        parts.push('PRIMARY KEY ("'+reflexiveRelationship.name+'_id","reflexive")')
        parts.push('CONSTRAINT "fk_' + @_formatTableName(reflexiveRelationship.entity.name) + '_' + reflexiveRelationship.name + '_id" FOREIGN KEY ("' + reflexiveRelationship.name + '_id") REFERENCES "' + @_formatTableName(reflexiveRelationship.destinationEntity.name) + '"("_id") ON DELETE CASCADE')
        parts.push('CONSTRAINT "fk_' + @_formatTableName(reflexiveRelationship.destinationEntity.name) + '_' + reflexiveRelationship.inverseRelationship().name + '" FOREIGN KEY ("reflexive") REFERENCES "' + @_formatTableName(reflexiveRelationship.entity.name) + '"("_id") ON DELETE CASCADE')

        sqls.push('CREATE TABLE IF NOT EXISTS "' + reflexiveTableName + '" (' + parts.join(',') + ')')

    return sqls

  columnTypeForAttribute:(attribute)->
    switch attribute.persistentType
      when 'tinyint'
        return 'smallint'
      when 'mediumint'
        return 'integer'
      when 'integer','int'
        return 'int'
      when 'bigint'
        return 'bigint'
      when 'timestamp'
        return 'bigint'
      when 'datetime','date'
        return 'timestamp with time zone'
      when 'bool','boolean'
        return 'boolean'
      when 'double'
        return 'double precision'
      when 'float'
        return 'real'
      when 'text'
        return 'text'
      when 'data'
        return 'bytea'
      else
        return super(attribute)


#  decodeValueForAttribute:(value,attribute)->
#    return super(value,attribute)

  encodeValueForAttribute:(value,attribute)->
    switch attribute.persistentType
      when 'boolean'
        return null if value is null
        return if value then 'yes' else 'no'
    return super(value,attribute)



class PostgreSQLConnection extends SQLConnection
  connect:(callback)->
    @connection = new pg.Client(@url)
    @connection.connect(callback)
    @connection.on('error',(err)=>
      @valid = no
      @log('postgres connection error',err)
    )

  close:()->
    @connection.end()

  execute:(query,callback)->
    @connection.query(query,(err,results)->
      callback(err,results?.rows)
    )

  createRow:(tableName,callback)->
    query = 'INSERT INTO "' + tableName + '" ("_id") VALUES (DEFAULT) RETURNING "_id"'
    @connection.query(query,(err,result)->
      return callback(err) if err
      callback(null,result.rows[0]._id)
    )



module.exports = PostgreSQLStore;
