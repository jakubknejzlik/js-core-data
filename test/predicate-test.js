var assert = require("assert"),
    Predicate = require('./../lib/FetchClasses/Predicate');

describe('Predicate',function(){
    it('should correctly format string',function(){
        var predicate = new Predicate('name = %s','aa');
        assert.equal(predicate.toString(),'name = \'aa\'');
    })
    it('should correctly format multiple strings',function(){
        var predicate = new Predicate('name = %s AND test = %s OR xxx = %s','aa','test','xxx');
        assert.equal(predicate.toString(),'name = \'aa\' AND test = \'test\' OR xxx = \'xxx\'');
    })
    it('should correctly format multiple numbers',function(){
        var predicate = new Predicate('name = %d AND test = %d OR xxx = %d',12,25,58);
        assert.equal(predicate.toString(),'name = 12 AND test = 25 OR xxx = 58');
    })
})