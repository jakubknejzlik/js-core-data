class SortDescriptor extends Object
  constructor:(@attribute,ascending = true)->
    if typeof ascending is 'string'
      ascending = ascending.toLowerCase() is 'ASC'
    @ascending = !!ascending
  toString: ->
    @attribute + ' ' + (if @ascending then 'ASC' else 'DESC')

module.exports = SortDescriptor