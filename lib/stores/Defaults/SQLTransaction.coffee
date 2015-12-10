class SQLTransaction
  constructor:(@connection,@store)->
    @started = no
    @autoRollback = yes
    @committed = no
    @rollbacked = no

  ensureBegin: (callback)->
    if @started
      return callback()
    @started = true
    @connection.query('BEGIN',(err)->
      callback(err)
    )

  query: (query,params,callback)->
    if @committed
      return callback(new Error('cannot send query to commited transaction'))
    if @rollbacked
      return callback(new Error('cannot send query to rolled back transaction'))

    if typeof params is 'function'
      callback = params
      params = undefined

    callback = @_wrapCallbackForAutoRollback(callback)

    if not @connection
      throw new Error('connection released or not set');

    @ensureBegin((err)=>
      return callback(err) if err
      @connection.query(query,params,callback);
    )

  commit: (callback)->
    if not @started
      @committed = yes
      return callback()
    if @committed
      return callback(new Error('cannot commit already commited transaction'))
    if @rollbacked
      return callback(new Error('cannot commit transaction after rollback'))
    @committed = yes
    @connection.query('COMMIT',callback);


  rollback: (callback)->
    if not @started
      return callback(new Error('cannot rollback transaction before begin'))
    if @committed
      return callback(new Error('cannot rollback transaction after commit'))
    if @rollbacked
      return callback(new Error('cannot rollback already rolled back transaction'))
    @rollbacked = yes
    @connection.query('ROLLBACK',callback);

  _wrapCallbackForAutoRollback:(callback)->
    _callback = callback
    if @autoRollback
      _callback = (err,results)=>
        if err
          @rollback(()->
            callback(err) if callback
          )
        else
          callback(err,results) if callback
    return _callback

  createRow:(tableName,callback)->
    callback = @_wrapCallbackForAutoRollback(callback)
    @ensureBegin((err)=>
      if err
        return callback(err)
      @connection.createRow(tableName,callback)
    )


module.exports = SQLTransaction