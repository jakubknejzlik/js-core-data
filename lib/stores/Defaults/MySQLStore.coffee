GenericSQLStore = require('./GenericSQLStore')
PersistentStoreRequest = require('./../PersistentStoreRequest')
GenericPool = require('generic-pool')
async = require('async')
ManagedObjectID = require('./../../ManagedObjectID')
Predicate = require('./../../FetchClasses/Predicate')
String = require('string')

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

    sqls.push('SET foreign_key_checks = 0')
    for key,entity of objectModel.entities
      sqls = sqls.concat(@createEntityQueries(entity,options.force))
    for key,entity of objectModel.entities
      sqls = sqls.concat(@createEntityRelationshipQueries(entity,options.force))
    sqls.push('SET foreign_key_checks = 1')

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
        parts.push(@_relationshipColumnDefinition(relationship))

    if force
      sqls = sqls.concat(@_dropEntityQueries(entity))
    sql = 'CREATE TABLE IF NOT EXISTS `' + tableName + '` ('
    sql += parts.join(',')
    sql += ') ENGINE=InnoDB  DEFAULT CHARSET=utf8'
    sqls.push(sql)

#    if not options.ignoreRelationships
#      sqls = sqls.concat(@createEntityRelationshipQueries(entity,force))

    return sqls

  _foreignKeyNameForRelationship:(relationship)->
    return 'fk_' + @_formatTableName(relationship.entity.name) + '_' + relationship.name + '_id'
  _foreignKeyDefinitionForRelationship:(relationship)->
    return 'CONSTRAINT `' + @_foreignKeyNameForRelationship(relationship) + '` FOREIGN KEY (`' + relationship.name + '_id`) REFERENCES `' + @_formatTableName(relationship.destinationEntity.name) + '`(`_id`) ON DELETE ' + relationship.getOnDeleteRule()




  _renameRelationshipQuery:(tableName,relationshipFrom,relationshipTo)->
    sqls = []
    sqls.push('ALTER TABLE ' + @quoteSymbol + tableName + @quoteSymbol + ' DROP FOREIGN KEY `' + @_foreignKeyNameForRelationship(relationshipFrom) + '`')
    sqls.push('ALTER TABLE ' + @quoteSymbol + tableName + @quoteSymbol + ' CHANGE ' + @quoteSymbol + relationshipFrom.name + '_id' + @quoteSymbol + ' ' + @quoteSymbol + relationshipTo.name + '_id' + @quoteSymbol + ' int(11) DEFAULT NULL')
    sqls.push('ALTER TABLE ' + @quoteSymbol + tableName + @quoteSymbol + ' ADD ' + @_foreignKeyDefinitionForRelationship(relationshipTo))
    return sqls.join(';')
  _renameAttributeQuery:(tableName,attributeFrom,attributeTo)->
    return 'ALTER TABLE ' + @quoteSymbol + tableName + @quoteSymbol + ' CHANGE ' + @quoteSymbol + attributeFrom.name + @quoteSymbol + ' ' + @_columnDefinitionForAttribute(attributeTo)
  _removeRelationshipQuery:(entityName,relationship)->
    columnName = relationship.name + '_id'
    return 'ALTER TABLE ' + @quoteSymbol + @_formatTableName(entityName) + @quoteSymbol + ' DROP FOREIGN KEY ' + @quoteSymbol + @_foreignKeyNameForRelationship(relationship) + @quoteSymbol + ';' + @_removeColumnQuery(entityName,columnName)
  _relationshipColumnDefinition:(relationship)->
    return super(relationship) + ',' + @_foreignKeyDefinitionForRelationship(relationship)


  createRelationshipQueries:(relationship,force)->
    sqls = []
    if relationship.toMany
      inversedRelationship = relationship.inverseRelationship()
      if inversedRelationship.toMany
        reflexiveRelationship = @_relationshipByPriority(relationship,inversedRelationship)
        reflexiveTableName = @_getMiddleTableNameForManyToManyRelation(reflexiveRelationship)
        if force
          sqls.push('DROP TABLE IF EXISTS `' + reflexiveTableName  + '`')

        parts = []

        parts.push('`'+reflexiveRelationship.name+'_id` int(11) NOT NULL')
        parts.push('`reflexive` int(11) NOT NULL')
        parts.push('PRIMARY KEY (`'+reflexiveRelationship.name+'_id`,`reflexive`)')
        parts.push('CONSTRAINT `fk_' + @_formatTableName(reflexiveRelationship.destinationEntity.name) + '_' + reflexiveRelationship.name + '_id` FOREIGN KEY (`' + reflexiveRelationship.name + '_id`) REFERENCES `' + @_formatTableName(reflexiveRelationship.destinationEntity.name) + '`(`_id`) ON DELETE CASCADE')
        parts.push('CONSTRAINT `fk_' + @_formatTableName(reflexiveRelationship.entity.name) + '_' + reflexiveRelationship.inverseRelationship().name + '` FOREIGN KEY (`reflexive`) REFERENCES `' + @_formatTableName(reflexiveRelationship.entity.name) + '`(`_id`) ON DELETE CASCADE')

        sqls.push('CREATE TABLE IF NOT EXISTS `' + reflexiveTableName + '` (' + parts.join(',') + ')')

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
    url = @url
    if ~url.indexOf('?')
      url += '&multipleStatements=yes'
    else url += '?multipleStatements=yes'
    @connection = mysql.createConnection(url)
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