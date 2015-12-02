GenericSQLStore = require('./GenericSQLStore')
PersistentStoreRequest = require('./../PersistentStoreRequest')
GenericPool = require('generic-pool')
async = require('async')
ManagedObjectID = require('./../../ManagedObjectID')
Predicate = require('./../../FetchClasses/Predicate')

SQLConnection = require('./SQLConnection')

try
  require('mysql')
catch e
  throw new Error('mysql module is required to use MySQL storage, please install it by running npm install --save mysql')

mysql = require('mysql')

_ = require('underscore');
_.mixin(require('underscore.inflections'));


class MySQLStore extends GenericSQLStore
  @::quoteSymbol = '`'

  createConnection:(url)->
    return new MySQLConnection(url,@)

  createSchemaQueries: (options = {})->
    objectModel = @storeCoordinator.objectModel
    sqls = []

    for key,entity of objectModel.entities
      sqls = sqls.concat(@createEntityQueries(entity,options.force))

    sqls.push('CREATE TABLE IF NOT EXISTS `_meta` (`key` varchar(10) NOT NULL,`value` varchar(250) NOT NULL,PRIMARY KEY (`key`)) ENGINE=InnoDB  DEFAULT CHARSET=utf8')
    sqls.push('INSERT INTO `_meta` VALUES(\'version\',\'' + objectModel.version + '\') ON DUPLICATE KEY UPDATE `value` = VALUES(`value`)')

    return sqls

  createEntityQueries:(entity,force,options = {})->
    sqls = []
    tableName = @_formatTableName(entity.name)
    parts = ['`_id` int(11) NOT NULL AUTO_INCREMENT','PRIMARY KEY (`_id`)']

    for attribute in entity.attributes
      columnDefinition = @_columnDefinitionForAttribute(attribute)
      if columnDefinition
        parts.push(columnDefinition);
      else
        throw new Error('unknown attribute type ' + attribute.type)

    for index in @_indexesForEntity(entity)
      parts.push((if index.type is 'unique' then 'UNIQUE ' else '') + 'KEY `'+index.name+'` (`'+index.columns.join('`,`')+'`)')

    for relationship in entity.relationships
      if not relationship.toMany
        parts.push(@relationshipColumnDefinition(relationship))

    if force
      sqls.push('DROP TABLE IF EXISTS `' + tableName + '`')
    sql = 'CREATE TABLE IF NOT EXISTS `' + tableName + '` ('
    sql += parts.join(',')
    sql += ') ENGINE=InnoDB  DEFAULT CHARSET=utf8;'
    sqls.push(sql)

    if not options.ignoreRelationships
      sqls = sqls.concat(@createEntityRelationshipQueries(entity,force))

    return sqls

  _renameRelationshipQuery:(tableName,relationshipFrom,relationshipTo)->
    return 'ALTER TABLE ' + @quoteSymbol + tableName + @quoteSymbol + ' CHANGE ' + @quoteSymbol + relationshipFrom.name + '_id' + @quoteSymbol + ' ' + @quoteSymbol + relationshipFrom.name + '_id' + @quoteSymbol + ' int(11) DEFAULT NULL'
  _renameAttributeQuery:(tableName,attributeFrom,attributeTo)->
    return 'ALTER TABLE ' + @quoteSymbol + tableName + @quoteSymbol + ' CHANGE ' + @quoteSymbol + attributeFrom.name + @quoteSymbol + ' ' + @_columnDefinitionForAttribute(attributeTo)


  createRelationshipQueries:(relationship,force)->
    sqls = []
    if relationship.toMany
      inversedRelationship = relationship.inverseRelationship()
      if inversedRelationship.toMany
        reflexiveRelationship = @_relationshipByPriority(relationship,inversedRelationship)
        reflexiveTableName = @_getMiddleTableNameForManyToManyRelation(reflexiveRelationship)
        if force
          sqls.push('DROP TABLE IF EXISTS `' + reflexiveTableName  + '`')
        sqls.push('CREATE TABLE IF NOT EXISTS `' + reflexiveTableName + '` (`'+reflexiveRelationship.name+'_id` int(11) NOT NULL,`reflexive` int(11) NOT NULL, PRIMARY KEY (`'+reflexiveRelationship.name+'_id`,`reflexive`))')
    return sqls

  columnTypeForAttribute:(attribute)->
    switch attribute.persistentType
      when 'enum'
        validValues = attribute.info.values
        if typeof validValues is 'string'
          validValues = validValues.split(',')
        return 'ENUM(\'' + validValues.join('\',\'') + '\')'
      else
        return super(attribute)



class MySQLConnection extends SQLConnection
  connect:(callback)->
    @connection = mysql.createConnection(@url,{multipleStatements:yes})
    @connection.connect((err)=>
      return callback(err) if err
      callback(null,@connection)
    )
    @connection.on('error',(err)->
      @valid = no
      @log('mysql connection error',err)
    )

  close:()->
    @connection.destroy()

  execute:(query,callback)->
    @connection.query(query,callback)

  createRow:(tableName,callback)->
    query = 'INSERT INTO ' + tableName+ ' (`_id`) VALUES (NULL)'
    @execute(query,(err,result)->
      return callback(err) if err
      callback(null,result.insertId)
    )


module.exports = MySQLStore;