var assert = require("assert"),
    SortDescriptor = require('./../lib/FetchClasses/SortDescriptor');

describe('SortDescriptor',function(){
    it('should correctly format ascending',function(){
        var sortDescriptor = new SortDescriptor('attribute');
        assert.equal(sortDescriptor.toString(),'attribute ASC');
        sortDescriptor = new SortDescriptor('attribute',true);
        assert.equal(sortDescriptor.toString(),'attribute ASC');
    })
    it('should correctly format descending',function(){
        var sortDescriptor = new SortDescriptor('attribute',false);
        assert.equal(sortDescriptor.toString(),'attribute DESC');
    })
})