moment = require('moment')

urlRegexp = new RegExp('^(ht|f)tp(s?)\:\/\/(([a-zA-Z0-9\-\._]+(\.[a-zA-Z0-9\-\._]+)+)|localhost)(\/?)([a-zA-Z0-9\-\.\?\,\'\/\\\+&amp;%\$#_]*)?([\d\w\.\/\%\+\-\=\&amp;\?\:\\\&quot;\'\,\|\~\;]*)$')
emailRegexp = new RegExp('^[0-9a-zA-Z]+([0-9a-zA-Z]*[-._+])*[0-9a-zA-Z]+@[0-9a-zA-Z]+([-.][0-9a-zA-Z]+)*([0-9a-zA-Z]*[.])[a-zA-Z]{2,6}$')

class AttributeValidator extends Object
  @validateValueForAttribute:(value,attribute)->
    switch attribute.type
      when 'string'
        if attribute.options.maxLength and value.toString().length > attribute.options.maxLength
          throw new Error('value \''+value+'\' longer than maxLength('+attribute.options.maxLength+') of attribute '+attribute.name)
        if attribute.options.minLength and value.toString().length < attribute.options.minLength
          throw new Error('value \''+value+'\' shorter than minLength('+attribute.options.minLength+') of attribute '+attribute.name)
        if attribute.options.regexp
          if !attribute.options._regexp
            v = attribute.options.regexp
            _re = []
            if v[0] is '/'
              v = v.substring(1)
              _re = v.split('/')
            else
              _re.push(v)
            attribute.options._regexp = new RegExp(_re[0],_re[1])
          if not attribute.options._regexp.test(value.toString())
            throw new Error('value \''+value+'\' does is not valid for regular expression('+attribute.options.regexp+') of attribute '+attribute.name)
        return yes

      when 'bool','boolean'
        if typeof value is 'string'
          value = value.toLowerCase().trim()
        switch value
          when true,false,'true','false','on','off','1','0','yes','no'
            return yes

      when 'date'
#        if typeof value is 'string'
#          value = new Date(value)
#        if value instanceof Date
#          return not isNaN(value.getTime())
        if value instanceof Date or (typeof value is 'string' and moment(new Date(value)).isValid())
          return yes
#        return yes

      when 'email'
        if emailRegexp.test(value)
          return yes

      when 'url'
        if urlRegexp.test(value)
          return yes

      when 'decimal','float','double'
        if !isNaN(parseFloat(value)) and isFinite(value)
          return yes

      when 'int','integer'
        if !isNaN(parseInt(value)) and isFinite(value) and parseInt(value,10) == parseFloat(value)
          return yes

      else return yes
    throw new Error('value \''+value+'\' ('+(typeof value)+') is not valid for attribute ' + attribute.name)

module.exports = AttributeValidator