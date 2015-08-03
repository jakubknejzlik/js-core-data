class SortDescriptor extends Object
  constructor:(@attribute,ascending = true)->
    @ascending = !!ascending
  toString: ->
    @attribute + ' ' + (if @ascending then 'ASC' else 'DESC')

module.exports = SortDescriptor