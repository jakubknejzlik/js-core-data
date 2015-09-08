moment = require('moment')
uuid = require('uuid')

class AttributeTransformer extends Object
  @transformedValueForAttribute:(value,attribute)->
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
        return parseFloat(value)

      when 'int','integer'
        return parseInt(value,10)

    return value

  @persistentValueForAttribute:(value,attribute)->
    switch attribute.type
      when 'timestamp'
        if typeof value is 'string'
          value = new Date(value)
        return moment(value).valueOf()

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