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
  throw new Error('sqlite3 module is required to user SQLite storage, please install it by running npm install --save sqlite3')

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
            sqls.push('DROP TABLE IF EXISTS `' + reflexiveTableName  + '`')
          sqls.push('CREATE TABLE IF NOT EXISTS `' + reflexiveTableName + '` (`'+reflexiveRelationship.name.toLowerCase()+'_id` int(11) NOT NULL,`reflexive` int(11) NOT NULL, PRIMARY KEY (`'+reflexiveRelationship.name.toLowerCase()+'_id`,`reflexive`))')
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