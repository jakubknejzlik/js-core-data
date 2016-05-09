var assert = require("assert");
var CoreData = require('../index');

var store_url = require('./get_storage_url');

var coreData = new CoreData(store_url,{
    logging:false
});

coreData.defineEntity('User',{
    username:{
        type: 'string',
        required: true
    },
    firstname: 'string',
    lastname: 'string'
})

describe('ManagedObject - required attributes', function(){
    before(function(done){
        coreData.syncSchema({force: true}).then(function(){
            done()
        }).catch(done)
    })

    it('should save object without all required attributes',function(done){
        var context = coreData.createContext()
        context.create('User',{
            username:'john.doe'
        })
        context.save().then(function(){
            done()
        }).catch(done)
    })

    it('should fail saving object without all required attributes',function(done){
        var context = coreData.createContext()
        context.create('User',{
            firstname: 'john',
            lastname: 'doe'
        })
        context.save().then(function(){
            done(new Error('should fail'))
        }).catch(function(err){
            console.log(err)
            done()
        })
    })
});