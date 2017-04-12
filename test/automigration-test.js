var assert = require('assert');
var tmp = require('tmp');
var fs = require('fs');
var async = require('async');


var CoreData = require('../index');

storeTmpName = tmp.tmpNameSync();
var store_url = require('./get_storage_url').replace(':memory:',storeTmpName);

describe('automigrations',function(){

    var db = new CoreData(store_url,{logging:false});

    var model1 = null
    var model2 = null

    before(function() {
        model1 = db.createModel('mig1')
        model2 = db.createModel('mig2')

        model1.defineEntity('User', {
            firstname: 'string',
            lastname: 'string'
        })
        model1.defineEntity('Token', {
            blah: 'string'
        })
        model1.defineRelationshipManyToMany('User', 'User', 'friends', 'friends')

        model2.defineEntity('User', {
            username: 'string',
            firstname2: 'string',
            lastname: 'string'
        })
        model2.defineEntity('Company', {
            name: 'string'
        })
        model2.defineEntity('Car', {
            model: 'string'
        })
        model2.defineRelationshipManyToOne('Company', 'User', 'users', 'company')
        model2.defineRelationshipManyToOne('Company', 'Car', 'cars', 'company')
        model2.defineRelationshipManyToMany('Car', 'Car', 'relatedCars', 'relatedCars')
    })

    it('should autogenerate migration', function () {
        var migrationGenerated = model2.autogenerateMigrationFromModel(model1)

        assert.deepEqual(migrationGenerated.entitiesChanges, [
            {entity: 'Company', change: '+'},
            {entity: 'Car', change: '+'},
            {entity: 'Token', change: '-'}
        ])
        assert.deepEqual(migrationGenerated.attributesChanges, {
            User: {
                username: '+',
                firstname2: '+',
                firstname: '-'
            }
        })
        console.log(migrationGenerated.relationshipsChanges)
        assert.deepEqual(migrationGenerated.relationshipsChanges, {
            User: {
                friends: '-',
                company: '+'
            }
        })
    })

    it('should not automigrate without automigration sync option', function () {
        db.setModelVersion('mig1')
        return db.syncSchema({force: true}).then(function() {
            console.log('?')
            db.setModelVersion('mig2')
            return db.syncSchema().catch(function(err) {
                assert.equal(err.message,'migration mig1=>mig2 not found')
            })
        })
    })

    it('should not automigrate with automigration sync option', function () {
        db.setModelVersion('mig1')
        return db.syncSchema({force: true}).then(function() {
            db.setModelVersion('mig2')
            return db.syncSchema({automigration: true})
        })
    })
});
