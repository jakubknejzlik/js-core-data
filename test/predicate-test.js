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
        objectID.stringValue = "xxxx/1";
        var predicate = new Predicate('object = %@ AND objectID =%@',object,objectID);
        assert.equal(predicate.toString(),'object._id = 1 AND objectID._id = 1');
        objectID.stringValue = "yyyy/2";
        predicate = new Predicate('object= %@ AND objectID=%@',object,objectID);
        assert.equal(predicate.toString(),'object._id = 2 AND objectID._id = 2');
    })
})