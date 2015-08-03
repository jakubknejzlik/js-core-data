moment = require('moment')

class AttributeTransformer extends Object
  @transformValueForAttribute:(value,attribute)->
    switch attribute.type

      when 'date'
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

module.exports = AttributeTransformer