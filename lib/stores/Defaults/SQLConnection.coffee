moment = require('moment')

SQLTransaction = require('./SQLTransaction')


class SQLConnection
  constructor:(@url,@store)->

  connect:(callback)->
    callback(new Error('not implemented'))

  close:(callback)->
    callback(new Error('not implemented'))

  query:(query,params,callback)->
    if typeof params is 'function'
      callback = params
      params = undefined
    query = @escapeQuery(query,params)
    if @store?.globals?.logging
      @store.globals.logging(query)
    @execute(query,(err,results)=>
      if err
        if @store?.globals?.logging
          @store.globals.logging('error in query:',query,', error:',err.message)
      callback(err,results)
    )

  execute:(query,params,callback)->
    callback(new Error('not implemented'))

  createRow:(tableName,callback)->
    callback(new Error('not implemented'))

  escapeQuery:(query,params)->
    params = params or []
    query = query.replace(/\?/g,()=>
      value = params.shift()
      value = @escapeValue(value)
      return value
    )
    return query

  escapeValue:(value)->
    if typeof value is 'string'
      return '\'' + value.replace(/'/g,'\'\'') + '\''
    else if value instanceof Date
      return '\'' + moment(value).format('YYYY-MM-DD HH:mm:ss') + '\''
    else if value is yes
      return '1'
    else if value is no
      return '0'
    else if not isNaN(value)
      return value
    return 'NULL'




module.exports = SQLConnection