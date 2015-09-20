emptyFn = (value)->
  return value
validateFn = ()->
  return yes

class AttributeType
  constructor:(@name,@persistentStoreType)->
    @transform = emptyFn
    @encode = emptyFn
    @decode = emptyFn
    @validate = validateFn

  transformFn:(fn)->
    @transform = fn
    @

  validateFn:(fn)->
    @validate = fn
    @

  encodeFn:(fn)->
    @encode = fn
    @

  decodeFn:(fn)->
    @decode = fn
    @

module.exports = AttributeType