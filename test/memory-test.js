var assert = require('assert');

var CoreData = require('../index');

var memwatch = require('memwatch-next');



describe('memory',function(){

    var cd = new CoreData('sqlite://:memory:',{logging:false})

    before(function(done){
        cd.defineEntity('MemoryTest',{
            attr1:'string'
        })
        cd.syncSchema({force:true},done);
    })

    it('should release memory on context destroy',function(){
        var hd = new memwatch.HeapDiff();
        var context = cd.createContext();

        for(var i = 0;i < 999;i++){
            var obj = context.create('MemoryTest');
            obj.attr1 = 'test ' + i;
        }

        context.destroy();
        var diff = hd.end();
        assert.ok(diff.before.size_bytes > diff.after.size_bytes);
    })

    it('should release memory on context destroy (saved context)',function(done){
        var context = cd.createContext();

        for(var i = 0;i < 999;i++){
            var obj = context.create('MemoryTest');
            obj.attr1 = 'test ' + i;
        }
        context.save().then(function(){
            var hd = new memwatch.HeapDiff();
            context.destroy();
            var diff = hd.end();
            assert.ok(diff.before.size_bytes > diff.after.size_bytes);
            done();
        }).catch(done);
    })
})