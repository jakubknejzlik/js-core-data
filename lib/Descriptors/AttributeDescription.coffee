PropertyDescription = require('./PropertyDescription')
AttributeType = require('./AttributeType')

moment = require('moment')
uuid = require('uuid')


attributeTypes = {}

class AttributeDescription extends PropertyDescription
  constructor:(@type,@info,name,entity) ->
    @persistentType = @getAttributeType(@info.persistentType or @type).persistentStoreType
    super(name,entity)

  @registerType:(type,aliases = [])->
    attributeTypes[type.name] = type
    for alias in aliases
      attributeTypes[alias] = type

  getAttributeType:()->
    if not attributeTypes[@type]
      throw new Error('unknown attribute type \'' + @type + '\'')
    return attributeTypes[@type]

  transform:(value)->
    if value is null
      return null
    return @getAttributeType().transform(value,@)


  decode:(value)->
    return @getAttributeType().decode(value,@)

  encode:(value)->
    if value is null
      return null
    return @getAttributeType().encode(value,@)


  defaultValue:()->
    value = @info?.default
    if typeof value is 'undefined'
      value = null
    return @transform(value)

  isPrivate:()->
    return !!@info.private

  isTransient:()->
    return !!@info.transient

  validateValue:(value)->
    if value is null
      return
    if not @getAttributeType().validate(value,@)
      throw new Error('value \''+value+'\' ('+(typeof value)+') is not valid for attribute ' + @name)

  toString: ->
    @name + '(' + @type + ')'

module.exports = AttributeDescription




urlRegexp = new RegExp('^(ht|f)tp(s?)\:\/\/(([a-zA-Z0-9\-\._]+(\.[a-zA-Z0-9\-\._]+)+)|localhost)(\/?)([a-zA-Z0-9\-\.\?\,\'\/\\\+&amp;%\$#_]*)?([\d\w\.\/\%\+\-\=\&amp;\?\:\\\&quot;\'\,\|\~\;]*)$')
emailRegexp = new RegExp('^[0-9a-zA-Z]+([0-9a-zA-Z]*[-._+])*[0-9a-zA-Z]+@[0-9a-zA-Z]+([-.][0-9a-zA-Z]+)*([0-9a-zA-Z]*[.])[a-zA-Z]{2,6}$')

floatTransform = (value)->
  value = parseFloat(value)
  if isNaN(value)
    value = null
  return value
floatValidate = (value,attribute)->
  float = parseFloat(value)
  if attribute.info.max and float > attribute.info.max
    throw new Error('value \''+value+'\' larger than max('+attribute.info.max+') of attribute '+attribute.name)
  if attribute.info.min and float < attribute.info.min
    throw new Error('value \''+value+'\' smaller than min('+attribute.info.min+') of attribute '+attribute.name)
  if !isNaN(parseFloat(value)) and isFinite(value)
    return yes

integerTransform = (value)->
  value = parseInt(value,10)
  if isNaN(value)
    value = null
  return value
integerValidate = (value,attribute)->
  int = parseInt(value)
  if attribute.info.max and int > attribute.info.max
    throw new Error('value \''+value+'\' larger than max('+attribute.info.max+') of attribute '+attribute.name)
  if attribute.info.min and int < attribute.info.min
    throw new Error('value \''+value+'\' smaller than min('+attribute.info.min+') of attribute '+attribute.name)
  if !isNaN(parseInt(value)) and isFinite(value) and parseInt(value,10) == parseFloat(value)
    return yes



AttributeDescription.registerType((new AttributeType('string','string')).validateFn((value,attribute)->
    if attribute.info.maxLength and value.toString().length > attribute.info.maxLength
      throw new Error('value \''+value+'\' larger than maxLength('+attribute.info.maxLength+') of attribute '+attribute.name)
    if attribute.info.minLength and value.toString().length < attribute.info.minLength
      throw new Error('value \''+value+'\' shorter than minLength('+attribute.info.minLength+') of attribute '+attribute.name)
    if attribute.info.regexp
      if !attribute.info._regexp
        v = attribute.info.regexp
        _re = []
        if v[0] is '/'
          v = v.substring(1)
          _re = v.split('/')
        else
          _re.push(v)
        attribute.info._regexp = new RegExp(_re[0],_re[1])
      if not attribute.info._regexp.test(value.toString())
        throw new Error('value \''+value+'\' does is not valid for regular expression('+attribute.info.regexp+') of attribute '+attribute.name)
    return yes
  )
)
AttributeDescription.registerType((new AttributeType('url','string')).validateFn((value,attribute)->
    if urlRegexp.test(value)
      return yes
  )
)
AttributeDescription.registerType((new AttributeType('email','string')).validateFn((value,attribute)->
    if emailRegexp.test(value)
      return yes
  )
)
AttributeDescription.registerType((new AttributeType('text','text')))
AttributeDescription.registerType((new AttributeType('data','data')))
AttributeDescription.registerType((new AttributeType('decimal','decimal')).transformFn(floatTransform).validateFn(floatValidate))
AttributeDescription.registerType((new AttributeType('float','float')).transformFn(floatTransform).validateFn(floatValidate))
AttributeDescription.registerType((new AttributeType('double','double')).transformFn(floatTransform).validateFn(floatValidate))
AttributeDescription.registerType((new AttributeType('integer','integer')).transformFn(integerTransform).validateFn(integerValidate),['int'])
AttributeDescription.registerType((new AttributeType('bigint','bigint')).transformFn(integerTransform).validateFn(integerValidate))
AttributeDescription.registerType((new AttributeType('date','date')).transformFn((value, attribute)->
    if value is null
      return null
    if value is 'now'
      value = new Date()
    return moment(value).toDate()
  ).validateFn((value)->
    if value in ['now']
      return yes
    if value instanceof Date or (typeof value is 'string' and moment(new Date(value)).isValid())
      return yes
  ).encodeFn((value)->
    if value is null
      return null
    return moment(value).toISOString()
  ).decodeFn((value)->
    if value is null
      return null
    return moment.utc(value).toDate()
  )
)
AttributeDescription.registerType((new AttributeType('timestamp','timestamp')).transformFn((value)->
    if value is null
      return null
    if value is 'now'
      value = new Date()
    if typeof value is 'string'
      value = new Date(value)
    return moment(value).toDate()
  ).validateFn((value)->
    if value in ['now']
      return yes
    if value instanceof Date or (moment(new Date(value)).isValid())
      return yes
  ).encodeFn((value)->
    if value is null
      return null
    return value.getTime()
  ).decodeFn((value)->
    if value is null
      return null
    return moment(Number(value)).toDate()
  )
)
AttributeDescription.registerType((new AttributeType('boolean','boolean')).transformFn((value)->
  if typeof value is 'string'
    value = value.toLowerCase().trim()
  switch value
    when true,'true',1,'1','on','yes'
      return yes
    else return no
).validateFn((value)->
  if typeof value is 'string'
    value = value.toLowerCase().trim()
  switch value
    when true,false,'true','false','on','off','1','0','yes','no',1,0
      return yes
)
,['bool'])

AttributeDescription.registerType((new AttributeType('enum','enum')).transformFn((value)->
  return String(value)
).validateFn((value,attribute)->
  if value is null
    return yes
  value = String(value)
  validValues = attribute.info.values
  if typeof validValues is 'string'
    validValues = validValues.split(',')
  if value not in validValues
    throw new Error('invalid value \'' + value + '\' for attribute ' + attribute.name + ' (possible values: ' + validValues.join(', ') + ')')
  return yes
))
AttributeDescription.registerType((new AttributeType('transformable','text')).transformFn((value)->
    if typeof value is 'string'
      value = JSON.parse(value)
    return value
  ).encodeFn((value)->
    return JSON.stringify(value)
  )
)
AttributeDescription.registerType((new AttributeType('uuid','string')).transformFn((value)->
    if value in ['uuid','uuidv4']
      value = uuid.v4()
    return value
  )
)
