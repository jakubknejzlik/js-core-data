var assert = require('assert');

var CoreData = require('../index');

var store_url = require('./get_storage_url');

describe('core module',function(){

    var cd = new CoreData(store_url)

    it('should should successfuly define entities',function(){
        cd.defineEntity('User',{
            username:{
                type:'string',
                unique:true
            },
            password:{
                type:'string',
                indexed: true
            }
        })
        assert.ok(cd.model.entities.User)

        cd.defineEntity('Company',{
            name:'string',
            identifier:'string'
        },{
            indexes:[
                'name',
                {columns:['name','identifier']}
            ]
        })

        cd.defineRelationship('Company','User','company',{inverse:'employers'})
        cd.defineRelationship('User','Company','employers',{toMany:true,inverse:'company'})

        assert.ok(cd.model.entities.Company)
    })

    it('should sync database scheme',function(done){
        cd.syncSchema({force:true},done)
    })

    it('should create context',function(done){
        var context = cd.createContext();
        var user = context.create('User');
        user.username = 'test';
        context.save(done);
    })

    it('should load data from store',function(done){
        var context = cd.createContext();
        context.getObject('User',{where:'SELF.username = "test"'},function(err,user){
            assert.ifError(err);
            assert.equal(user.username,'test');
            context.save(done);
        });
    })

    it('should load objects',function(done){
        var context = cd.createContext();
        context.getObjects('User',function(err,users){
            user = users[0]
            assert.ifError(err);
            context.deleteObject(user);
            context.save(function(err){
                assert.ifError(err);
                context.getObject('User',{where:'SELF.username = "test"'},function(err,user){
                    assert.ifError(err);
                    assert.ok(!user);
                    done();
                })
            })
        });
    })
})