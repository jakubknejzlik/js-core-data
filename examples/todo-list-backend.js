var CoreData = require('../index');
var express = require('express');
var passport = require('passport');
var BearerStrategy = require('passport-http-bearer');
var sha512 = require('js-sha512');
var bodyParser = require('body-parser');

var app = new express();
var db = new CoreData('sqlite://:memory:',{logging:false});

app.db = db;
// define model

db.defineEntity('User',{
    username:{type:'string',unique:true},
    password:'string'
});
db.defineEntity('AccessToken',{
    token:{
        unique:true,
        type:'uuid',
        default:'uuidv4'
    }
});
db.defineEntity('Task',{
    name:'string',
    completed:'boolean'
});

db.defineRelationshipOneToMany('User','AccessToken','accessTokens','owner');
db.defineRelationshipOneToMany('User','Task','tasks','owner');


// Create Authentication methods
passport.use(new BearerStrategy(function(token,done) {
    var authContext = db.createContext();
    authContext.getObject('User', {where: ['SELF.accessTokens.token = %s', token]}, function (err, user) {
        if (!user) return done(new Error('user not found'));
        authContext.destroy();
        done(err, user.objectID);
    });
}));

app.use(db.middleware());
app.use(bodyParser.json());

app.post('/register',function(req,res,next){
    if (!req.body.username || !req.body.password) return next(new Error('username and password must be specified'));
    var password = sha512(req.body.password);
    var user = req.context.create('User',{username:req.body.username,password:password});
    var token = req.context.create('AccessToken');
    token.setOwner(user);
    req.url = '/authorize';
    res.status(201);
    req.context.save().then(next).catch(next);
});

app.post('/authorize',function(req,res,next){
    var username = req.body.username;
    var password = req.body.password;
    var passwordHash = sha512(password);
    req.context.getObject('User',{where:['SELF.username = %s AND SELF.password = %s',username,passwordHash]}).then(function(user){
        if (!user) return next(new Error('user not found'));
        var token = req.context.create('AccessToken');
        user.addAccessToken(token);
        return req.context.save().then(function(){
            res.send({user:user,token:token.token});
        })
    }).catch(next);
});

app.use(passport.authenticate('bearer',{session:false}),function(req,res,next){
    req.context.getObjectWithObjectID(req.user).then(function(user){
        req.user = user;
        next();
    }).catch(next);
});

app.get('/me',function(req,res,next){
    res.send(req.user);
});


// task methods
app.get('/me/tasks',function(req,res,next){
    req.user.getTasks().then(function(tasks){
        res.send(tasks);
    }).catch(next);
});

app.post('/me/tasks',function(req,res,next){
    var task = req.context.create('Task',req.body);
    req.user.addTask(task);
    req.context.save().then(function(){
        res.status(201).send(task);
    }).catch(next);
});

app.all('/me/tasks/:id',function(req,res,next){
    req.context.getObject('Task',{where:['SELF._id = %d AND SELF.owner = %@',req.params.id,req.user]}).then(function(task){
        req.task = task;
        next();
    }).catch(next);
});
app.get('/me/tasks/:id',function(req,res,next){
    res.send(req.task);
});
app.put('/me/tasks/:id',function(req,res,next){
    req.task.setValues(req.body);
    req.context.save().then(function(){
        res.send(req.task);
    }).catch(next);
});
app.delete('/me/tasks/:id',function(req,res,next){
    req.context.deleteObject(req.task);
    req.context.save().then(function(){
        res.send(req.task);
    }).catch(next);
});


// error handling
//app.use(function(err,req,res,next){
//    res.status(400).send({error:err.message});
//});

module.exports = app;