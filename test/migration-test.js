var assert = require('assert');

var CoreData = require('../index');

describe.only('migrations',function(){

    var db = new CoreData('sqlite://:memory:')

    before(function(){
        model1 = db.createModel('0.1');
        model1.defineEntity('User',{
            firstname:'string',
            lastname:'string'
        });
        model1.defineEntity('Company',{
            name:'string'
        });

        model2 = db.createModel('0.2');
        model2.defineEntity('User',{
            firstname:'string',
            lastname:'string',
            password:'string'
        });
        model2.defineEntity('Company',{
            name:'string'
        });

        migration1to2 = model2.createMigrationFrom(model1);
        migration1to2.addAttribute('User','password');

    })

    it('should sync schema to 0.1',function(done){
        db.setModelVersion('0.2');
        db.syncSchema(done);
    })
})