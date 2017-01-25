util = require('util')
ManagedObject = require('./../ManagedObject')
ManagedObjectID = require('./../ManagedObjectID')
moment = require('moment')

DATE_FORMAT = 'YYYY-MM-DD HH:mm:ss'

numberRegExp = /\!(-?[0-9\.]+)\!/g
nanRegExp = /\!NaN\!/g
stringRegExp = /'[^']+'/g
columnNameRegExp = /([a-z_][\w]+)/g
columnFunctionRegExp = /([\w]+(\())|(\sAS\s\w+(\)))/g

operators = {
  '>=':'>=',
  '<=':'<=',
  '!?':'NOT LIKE'
  '>':'>',
  '<':'<',
  '!':'<>'
  '?':'LIKE'
}

class Predicate extends Object
  constructor: (@format,@variables...)->
    @variables = @escapeArrayValues(@variables)

  isObjectIDPredicate:->
    return @format instanceof ManagedObjectID

  objectID:->
    @format

  escapeArrayValues:(array)->
    return array.map(@escapeValue.bind(@))


  escapeValue:(value)->
    if Array.isArray(value)
      return @escapeArrayValues(value)
    else if typeof value is 'string'
      value = value.replace(/'/g,"''")
    return value

  parseObjectCondition:(object, join = 'AND', tableAlias = 'SELF')->
    predicates = []

    if typeof object is 'string'
      object = new Predicate('(' + object + ')')
    if object instanceof Predicate
      return object.toString(@tableAlias)
    else if Array.isArray(object)
      for item in object
        predicates.push(@parseObjectCondition(item))
    else
      for key,value of object

        operator = '='
        for signature,_operator of operators
          if key.indexOf(signature) isnt -1
            operator = _operator
            key = key.replace(signature,'')
            break

        if key not in ['$or','$and']
          cleanKey = key.replace(stringRegExp,'___').replace(columnFunctionRegExp,'!$2$4').replace(new RegExp(tableAlias + '(\\.[\\w_0-9]+)+','gi'),'!')
          matches = cleanKey.match(columnNameRegExp)
          if matches
            for match in matches
              key = key.replace(match,tableAlias + '.' + match)

        if value is null
          if operator is '<>'
            predicates.push(new Predicate(key + ' IS NOT NULL'))
          else
            predicates.push(new Predicate(key + ' IS NULL'))
        else if key is '$or'
          predicates.push(@parseObjectCondition(value,'OR'))
        else if key is '$and'
          predicates.push(@parseObjectCondition(value,'AND'))
        else if Array.isArray(value) and value.length > 0
          predicates.push(new Predicate(key + ' IN %a',value))
        else if typeof value is 'number'
          predicates.push(new Predicate(key + ' ' + operator + ' %d',value))
        else if typeof value is 'boolean'
          predicates.push(new Predicate(key + ' ' + operator,if value then 'TRUE' else 'FALSE'))
        else if typeof value is 'string'
          if operator in ['LIKE','NOT LIKE']
            predicates.push(new Predicate(key + ' ' + operator + ' %s',value.replace(/\*/g,'%').replace(/\?/g,'_')))
          else
#            if isFinite(value)
#              predicates.push(new Predicate(key + ' ' + operator + ' %d',value))
#            else
            predicates.push(new Predicate(key + ' ' + operator + ' %s',value))
        else
          if value instanceof Date
            predicates.push(new Predicate(key + ' ' + operator + ' %s',moment(value).format(DATE_FORMAT)))
          else if value instanceof ManagedObject
            predicates.push(new Predicate(key + '_id ' + operator + ' %d',value.objectID.recordId()))
          else if value instanceof ManagedObjectID
            predicates.push(new Predicate(key + '_id ' + operator + ' %d',value.recordId()))
          else if value and value._isAMomentObject
            predicates.push(new Predicate(key + ' ' + operator + ' %s',value.format(DATE_FORMAT)))

    predicates = predicates.filter((x) -> return x)
    if predicates.length is 0
      return null
    string = predicates.map((x)-> return x.toString()).join(' ' + join + ' ')
    return '(' + string + ')'

  toString:(tableAlias = 'SELF')->
    if @format instanceof ManagedObjectID
      return '_id = ' + @format.recordId();
    else
      if typeof @format is 'object'
        return @parseObjectCondition(@format, undefined, tableAlias) or 'TRUE'

      format = @format.replace(/[\s]*(!?=)[\s]*%@/g,'_id $1 %d').replace(/%s/g,'\'%s\'').replace(/%a/g,'%s').replace(/%d/g,'!%d!')

      args = [format]
      for variable in @variables
        if variable is undefined or variable is null
          variable = null
        else if util.isArray(variable)
          variable = '(' + variable.map((x)->
              if typeof x is 'string'
                return '\'' + x.replace(/'/g,'\'') + '\''
              return x
            ).join(',') + ')'
        else if variable instanceof Date
          variable = moment(variable).format(DATE_FORMAT)
        else if variable instanceof ManagedObject
          variable = variable.objectID.recordId()
        else if variable instanceof ManagedObjectID
          variable = variable.recordId()
        else if variable and variable._isAMomentObject
          variable = variable.format(DATE_FORMAT)
        args.push(variable)

      string = util.format.apply(util.format,args);

      string = string.replace(numberRegExp,'$1')
      string = string.replace(nanRegExp,'\'[NaN]\'')

      return string

module.exports = Predicate