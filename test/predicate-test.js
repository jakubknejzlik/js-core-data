var assert = require("assert"),
    Predicate = require('./../lib/FetchClasses/Predicate'),
    moment = require('moment'),
    ManagedObject = require('../lib/ManagedObject'),
    ManagedObjectID = require('../lib/ManagedObjectID');

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
    it('should correctly format dates',function(){
        var date = moment();
        var date2 = new Date();
        var predicate = new Predicate('date = %s AND date2 = %s',date,date2);
        assert.equal(predicate.toString(),'date = \'' + date.format('YYYY-MM-DD HH:mm:ss') + '\' AND date2 = \'' + moment(date2).format('YYYY-MM-DD HH:mm:ss')+'\'');
    })
    it('should correctly format Objects and ObjectIDs',function(){
        var objectID = new ManagedObjectID();
        var object = new ManagedObject();
        object._objectID = objectID;
        objectID.stringValue = "xxxx/p1";
        var predicate = new Predicate('object = %@ AND objectID =%@',object,objectID);
        assert.equal(predicate.toString(),'object_id = 1 AND objectID_id = 1');
        predicate = new Predicate('object != %@ AND objectID !=%@',object,objectID);
        assert.equal(predicate.toString(),'object_id != 1 AND objectID_id != 1');
        objectID.stringValue = "yyyy/p2";
        predicate = new Predicate('object= %@ AND objectID=%@',object,objectID);
        assert.equal(predicate.toString(),'object_id = 2 AND objectID_id = 2');
        objectID.stringValue = "yyyy/o2";
        predicate = new Predicate('object= %@ AND objectID=%@',object,objectID);
        assert.equal(predicate.toString(),'object_id = NaN AND objectID_id = NaN');
    })
    it('should correctly format undefined values',function(){
        var predicate = new Predicate('attr1 = %d AND attr2 = %s AND attr3 = %@','aa',undefined,undefined);
        assert.equal(predicate.toString(),"attr1 = NaN AND attr2 = 'null' AND attr3_id = 0");
    })
    it('should correctly format undefined arrays',function(){
        var predicate = new Predicate('attr1 IN %a AND attr2 IN %a AND attr3 IN %a',['a','b'],[1,2],['aa',1]);
        assert.equal(predicate.toString(),"attr1 IN (\"a\",\"b\") AND attr2 IN (1,2) AND attr3 IN (\"aa\",1)");
    })
})