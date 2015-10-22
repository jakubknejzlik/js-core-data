var supertest = require('supertest');
var assert = require('assert');

var app = require('../examples/todo-list-backend');

var test = supertest(app);


describe('todo',function(){
    before(function(done){
        app.db.syncSchema({force:true}).then(done).catch(done);
    });

    var user = {username:'john',password:'doe'};
    it('should register user',function(done){
        test.post('/register')
            .send(user)
            .expect(201)
            .end(function(err,res){
                assert.ifError(err);
                assert.ok(res.body.token);
                assert.equal(res.body.user.username,user.username);
                done();
            });
    });

    it('should authorize registered user',function(done){
        test.post('/authorize')
            .send(user)
            .expect(200)
            .end(function(err,res){
                assert.ifError(err);
                assert.ok(res.body.token);
                assert.equal(res.body.user.username,user.username);
                done();
            });
    });

    describe('authorized user',function(){
        var accessToken = null;
        var task = {name:'test task',completed:false};

        before(function(done){
            test.post('/authorize')
                .send(user)
                .expect(200)
                .end(function(err,res){
                    assert.ifError(err);
                    assert.ok(res.body.token);
                    accessToken = res.body.token;
                    done();
                });
        });

        it('should display user info',function(done){
            test.get('/me?access_token=' + accessToken)
                .expect(200)
                .end(function(err,res){
                    assert.ifError(err);
                    assert.equal(res.body.username,user.username);
                    done();
                });
        });


        it('should create task',function(done){
            test.post('/me/tasks?access_token=' + accessToken)
                .send(task)
                .expect(201)
                .end(function(err,res){
                    assert.ifError(err);
                    assert.equal(res.body.name,task.name);
                    assert.ok(res.body.id);
                    task.id = res.body.id;
                    done();
                });
        });


        it('should see created task',function(done){
            test.get('/me/tasks?access_token=' + accessToken)
                .expect(200)
                .end(function(err,res){
                    assert.ifError(err);
                    assert.equal(res.body.length,1);
                    assert.equal(res.body[0].name,task.name);
                    done();
                });
        });
        it('should see created task detail',function(done){
            test.get('/me/tasks/' + task.id + '?access_token=' + accessToken)
                .expect(200)
                .end(function(err,res){
                    assert.ifError(err);
                    assert.equal(res.body.name,task.name);
                    done();
                });
        });
        it('should update created task',function(done){
            test.put('/me/tasks/' + task.id + '?access_token=' + accessToken)
                .send({name:'updated task name'})
                .expect(200)
                .end(function(err,res){
                    assert.ifError(err);
                    assert.equal(res.body.name,'updated task name');
                    done();
                });
        });
        it('should delete created task',function(done){
            test.del('/me/tasks/' + task.id + '?access_token=' + accessToken)
                .expect(200,done)
        });
        it('shouldn\'t see deleted task',function(done){
            test.get('/me/tasks?access_token=' + accessToken)
                .expect(200)
                .end(function(err,res){
                    assert.ifError(err);
                    assert.equal(res.body.length,0);
                    done();
                });
        });
    })
});