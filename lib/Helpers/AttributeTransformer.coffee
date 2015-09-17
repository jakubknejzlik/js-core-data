moment = require('moment')
uuid = require('uuid')

class AttributeTransformer extends Object
  @transformedValueForAttribute:(value,attribute)->
    if value is null
      return null

    switch attribute.type

      when 'date','timestamp'
        if typeof value is 'string'
          value = new Date(value)
        return moment(value).toDate()

      when 'bool','boolean'
        if typeof value is 'string'
          value = value.toLowerCase().trim()
        switch value
          when true,'true',1,'1','on','yes'
            return yes
          else return no

      when 'decimal','double','float'
        value = parseFloat(value)
        if isNaN(value)
          value = null
        return value

      when 'int','integer'
        value = parseInt(value,10)
        if isNaN(value)
          value = null
        return value

      when 'transformable'
        if typeof value is 'string'
          value = JSON.parse(value)
        return value

    return value



  @persistentValueForAttribute:(value,attribute)->
    if value is null
      return null

    switch attribute.type
      when 'timestamp'
        if typeof value is 'string'
          value = new Date(value)
        return moment(value).valueOf()
      when 'transformable'
        console.log(value)
        return JSON.stringify(value)

    return value

  @defaultValueForAttribute:(attribute)->
    switch attribute.type
      when 'uuid'
        if attribute.info?.default in ['uuid','uuidv4']
          return uuid.v4()
      when 'date'
        if attribute.info?.default in ['now']
          return moment()

    return attribute.info?.default or null


module.exports = AttributeTransformer