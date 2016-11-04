GenericPool = require('generic-pool')
URL = require('url')
querystring = require('querystring')

SQLTransaction = require('./SQLTransaction')

class SQLConnectionPool
  constructor: (url,createConnectionFunction,@store,settings)->
    urlOptions = querystring.parse(URL.parse(url).query)
    @pool = GenericPool.Pool({
      name     : "sql-connection-pool",
      create   : (callback)=>
        connection = createConnectionFunction(url)
        connection.connect((err)->
          return callback(err) if err
          callback(null,connection)
        )
      destroy  : (connection)->
        connection.close()
      validate: (connection)->
        return connection.valid
      max : settings.maxConnections or urlOptions.maxConnections or 1 #settings?.maxConnections or (if process.NODE_ENV is 'production' then 100 else 10),
      idleTimeoutMillis : settings?.idletimeoutMillis ? 60*1000,
      reapIntervalMillis : settings?.reapIntervalMillis ? 5*1000
      log: @store.globals.logging or @store.globals.poolLogging
    })

  query: (query,params,callback)=>
    if typeof params is 'function'
      callback = params
      params = null
    @pool.acquire (err,connection)=>
      return callback?(err) if err
      connection.query(query,params,(err,results)=>
        @pool.release(connection)
        callback?(err,results)
      )

  createTransaction: (callback)->
    @pool.acquire((err,connection)=>
      if err
        return callback(err)
      callback(null,new SQLTransaction(connection,@store))
    )

  releaseTransaction: (transaction)->
    @pool.release(transaction.connection);

  closeAllConnections: (callback)->
    @pool.destroyAllNow(callback)

module.exports = SQLConnectionPool
