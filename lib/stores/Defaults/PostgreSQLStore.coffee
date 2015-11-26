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

  createSchemaQueries: (options = {})->
    objectModel = @storeCoordinator.objectModel
    sqls = []

    for key,entity of objectModel.entities
      sqls = sqls.concat(@createEntityQueries(entity,options.force))

    sqls.push('CREATE TABLE IF NOT EXISTS "_meta" ("key" varchar(10) NOT NULL,"value" varchar(250) NOT NULL,PRIMARY KEY ("key"))')
    sqls.push('DELETE FROM "_meta" WHERE ' + @quoteSymbol + 'key' + @quoteSymbol + ' = \'version\'')
    sqls.push('INSERT INTO "_meta" VALUES(\'version\',\'' + objectModel.version + '\')')

    return sqls

  createEntityQueries:(entity,force = no,options = {})->
    sqls = []
    tableName = @_formatTableName(entity.name)
    parts = ['"_id" SERIAL PRIMARY KEY']

    for attribute in entity.attributes
      columnDefinition = @_columnDefinitionForAttribute(attribute)
      if columnDefinition
        parts.push(columnDefinition);
      else
        throw new Error('unknown attribute type ' + attribute.type)

    for relationship in entity.relationships
      if not relationship.toMany
        parts.push('"'+relationship.name+'_id" int DEFAULT NULL')

    if force
      sqls.push('DROP TABLE IF EXISTS "' + tableName + '"')
    sql = 'CREATE TABLE IF NOT EXISTS "' + tableName + '" ('
    sql += parts.join(',')
    sql += ')'

    for index in @_indexesForEntity(entity)
      sql +=';CREATE ' + (if index.type is 'unique' then 'UNIQUE' else '') + ' INDEX "'+index.name+'" ON "'+tableName+'" ("'+index.columns.join('","')+'")'

    sqls.push(sql)

    if not options.ignoreRelationships
      sqls = sqls.concat(@createEntityRelationshipQueries(entity,force))

    return sqls

  createEntityRelationshipQueries:(entity,force)->
    sqls = []
    for key,relationship of entity.relationships
      if relationship.toMany
        inversedRelationship = relationship.inverseRelationship()
        if inversedRelationship.toMany
          reflexiveRelationship = @_relationshipByPriority(relationship,inversedRelationship)
          reflexiveTableName = @_getMiddleTableNameForManyToManyRelation(reflexiveRelationship)
          if force
            sqls.push('DROP TABLE IF EXISTS "' + reflexiveTableName  + '"')
          sqls.push('CREATE TABLE IF NOT EXISTS "' + reflexiveTableName + '" ("'+reflexiveRelationship.name+'_id" serial NOT NULL,"reflexive" serial NOT NULL, PRIMARY KEY ("'+reflexiveRelationship.name+'_id","reflexive"))')
    return sqls

  columnTypeForAttribute:(attribute)->
    switch attribute.persistentType
      when 'tinyint'
        return 'smallint'
      when 'mediumint'
        return 'integer'
      when 'integer','int'
        return 'int'
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

  processQuery:(query)->
    regString = query.replace(new RegExp('\'[^\']+\'','g'),'\'ignored\'')
    columnRegExp = new RegExp('SELF[\\w_]*(\\.[\\w_]+)+','gi')
    matches = regString.match(columnRegExp)
    for match in matches
      column = match.replace(/\./g,'\.')
      columnAfter = match.replace(/\.([^\.]+)$/g,'."$1"')
      query = query.replace(new RegExp(column,'g'),columnAfter)

    return query


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

  close:()->
    @connection.end()

  execute:(query,callback)->
    @connection.query(query,(err,results)->
      callback(err,results?.rows)
    )

  createRow:(tableName,callback)->
    query = 'INSERT INTO ' + tableName + ' ("_id") VALUES (DEFAULT) RETURNING "_id"'
    @connection.query(query,(err,result)->
      return callback(err) if err
      callback(null,result.rows[0]._id)
    )



module.exports = PostgreSQLStore;