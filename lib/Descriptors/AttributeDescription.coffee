PropertyDescription = require('./PropertyDescription')


class AttributeDescription extends PropertyDescription
  constructor:(@type,@info,name,entity) ->
    super(name,entity)


  toString: ->
    @name + '(' + @type + ')'

module.exports = AttributeDescription