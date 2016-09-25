var assert = require("assert"),
    FetchRequest = require('./../lib/FetchRequest'),
    Predicate = require('./../lib/FetchClasses/Predicate'),
    SortDescriptor = require('./../lib/FetchClasses/SortDescriptor'),
    CoreData = require('../index');

var store_url = 'sqlite://:memory:';

describe('SQL Store',function(){
    var cd = new CoreData(store_url)

    var User = cd.defineEntity('User',{username:'string'})
    var Company = cd.defineEntity('Company',{name:'string'})
    var Team = cd.defineEntity('Team',{name:'string'})
    cd.defineRelationshipManyToOne('User','Company','company','users')
//    cd.defineRelationship('Company','User','users',{toMany:true,inverse:'company'})
    cd.defineRelationshipManyToMany('User','Team','teams','users')
//    cd.defineRelationship('Team','User','users',{toMany:true,inverse:'teams'})

    var context = cd.createContext();
    var store = context.storeCoordinator.persistentStores[0];

//    before(function(done){
//        cd.syncSchema(done)
//    })

    it('should format SQL',function(){
        var req = new FetchRequest(User,new Predicate('username = %s','test'),[new SortDescriptor('username')]);
        var sql = store.sqlForFetchRequest(req);
        assert.equal(sql,"SELECT SELF.\"_id\" AS \"_id\", SELF.\"username\" AS \"username\", SELF.\"company_id\" AS \"company_id\" FROM \"users\" SELF WHERE (username = 'test') GROUP BY SELF.\"_id\" ORDER BY SELF.\"username\" ASC")
    })

    it('should format SQL with joins for oneToMany',function(){
        var req = new FetchRequest(User,new Predicate('SELF.company.name = %s','test'),[new SortDescriptor('SELF.company.name')]);
        var sql = store.sqlForFetchRequest(req);
        assert.equal(sql,"SELECT SELF.\"_id\" AS \"_id\", SELF.\"username\" AS \"username\", SELF.\"company_id\" AS \"company_id\" FROM \"users\" SELF LEFT JOIN \"companies\" SELF_company ON (SELF_company.\"_id\" = SELF.\"company_id\") WHERE (SELF_company.\"name\" = 'test') GROUP BY SELF.\"_id\" ORDER BY SELF_company.\"name\" ASC")
    })

    it('should format SQL with joins for manyToOne',function(){
        var req = new FetchRequest(Company,new Predicate('SELF.users.username = %s','test'),[new SortDescriptor('SELF.users.username')]);
        var sql = store.sqlForFetchRequest(req);
        assert.equal(sql,"SELECT SELF.\"_id\" AS \"_id\", SELF.\"name\" AS \"name\" FROM \"companies\" SELF LEFT JOIN \"users\" SELF_users ON (SELF_users.\"company_id\" = SELF.\"_id\") WHERE (SELF_users.\"username\" = 'test') GROUP BY SELF.\"_id\" ORDER BY SELF_users.\"username\" ASC")
    })

    it('should format SQL with joins for manyToMany',function(){
        var req = new FetchRequest(User,new Predicate('SELF.teams.name = %s','test'),[new SortDescriptor('SELF.teams.name')]);
        var sql = store.sqlForFetchRequest(req);
        assert.equal(sql,"SELECT SELF.\"_id\" AS \"_id\", SELF.\"username\" AS \"username\", SELF.\"company_id\" AS \"company_id\" FROM \"users\" SELF LEFT JOIN \"teams_users\" SELF_teams__mid ON (SELF.\"_id\" = SELF_teams__mid.\"users_id\") LEFT JOIN \"teams\" SELF_teams ON (SELF_teams__mid.\"reflexive\" = SELF_teams.\"_id\") WHERE (SELF_teams.\"name\" = 'test') GROUP BY SELF.\"_id\" ORDER BY SELF_teams.\"name\" ASC")

        req = new FetchRequest(Team,new Predicate('SELF.users.username = %s','test'),[new SortDescriptor('SELF.users.username')]);
        sql = store.sqlForFetchRequest(req);
        assert.equal(sql,"SELECT SELF.\"_id\" AS \"_id\", SELF.\"name\" AS \"name\" FROM \"teams\" SELF LEFT JOIN \"teams_users\" SELF_users__mid ON (SELF.\"_id\" = SELF_users__mid.\"reflexive\") LEFT JOIN \"users\" SELF_users ON (SELF_users__mid.\"users_id\" = SELF_users.\"_id\") WHERE (SELF_users.\"username\" = 'test') GROUP BY SELF.\"_id\" ORDER BY SELF_users.\"username\" ASC")
    })
})