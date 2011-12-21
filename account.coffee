form     = require 'express-form'
passport = require 'passport'
nconf    = require 'nconf'
passport = require 'passport'

passwd   = require './passwd'

LocalStrategy = require('passport-local').Strategy

passport.use new LocalStrategy( {
    usernameField: 'uid',
    passwordField: 'password'
  },
  (username, password, done)->
      console.log "Auth #{username}"
      return done(null, {id:username})
)

passport.serializeUser (user, done)->
    done(null, user.id)

passport.deserializeUser (id, done)->
    done(null, {id})

MEGANON='anton'

AFTER_LOGIN = '/app'

cache = []

class Account

    constructor: (@posix) ->
        @uid = @posix.username
        @home = "/home/#{@uid}"
        @email = nconf.get("user:#{@uid}:email")

    save: (cb) ->
        nconf.set("user:#{@uid}:email", @email )
        nconf.save cb

# Reload PAM users cache
exports.reload = (cb)->
    passwd.getAll (usr)->
        cache = (usr or []).map (u) -> new Account(u)
        cb and cb(null, cache)

# Find user by UID in cache
exports.find = (uid)->
    for u in cache
        if u.uid == uid then return u
    null

# Check if user exists in cache
exports.exists = (uid)-> exports.find(uid) != null
    
# Create PAM user
exports.create = (params, cb)->
    passwd.add params.uid, params.passwd, {createHome:true,sudo:true}, (code)->
        if code != 0 then return cb and cb( new Error("Can't create user") )
        exports.reload (err) ->
            account = exports.find( params.uid )
            account.email = params.email
            account.save cb

# PAM auth: Curently stub is here
exports.auth = (uid, password, cb) ->
    cb and cb( new Error('Invalid password or username') )

exports.ensure_login = (req, resp, next) ->
    req.session.uid ?= MEGANON
    if req.session.uid
        next()
    else
        next( new Error('User not authorized') )

exports.force_login = (req, resp, next) ->
    req.session.uid ?= MEGANON
    if req.session.uid
        next()
    else
        resp.redirect '/login?next=' + req.path

# Init view and user cache
exports.init = (app, cb)->

    validate_uid = (uid) ->
        if exports.exists uid
            throw new Error('Account with this ID already taken')

    validate_uid_form = form(
        form.filter("uid").trim().toLower(),
        form.validate("uid").required().is(/^[a-z0-9_]+$/).custom( validate_uid ),
    )

    validate_register_form = form(
        form.filter("uid").trim().toLower(),
        form.validate("uid").required().is(/^[a-z0-9_]+$/).custom( validate_uid ),
        form.filter("email").trim(),
        form.validate("email").required().isEmail(),
        form.validate("password").required()
    )

    validate_login_form = form(
        form.filter("uid").trim().toLower(),
        form.validate("uid").required().is(/^[a-z0-9_]+$/),
        form.validate("password").required()
    )

    validate_account_form = form(
        form.filter("email").trim(),
        form.validate("email").required().isEmail(),
        form.validate("password")
    )

    app.get '/validate/uid', validate_uid_form, (req, resp) ->
        resp.send JSON.stringify if not req.form.isValid then req.form.errors.join('<br/>') else true

    app.get '/register', (req, resp) ->
        next = req.param('next', AFTER_LOGIN )
        resp.render 'register', {next:next}

    app.post '/register', validate_register_form, (req, resp) ->
        next = req.param('next', AFTER_LOGIN)
        if not req.form.isValid
            resp.render 'register', { error:req.form.errors.join('<br/>'), next:next }
        else
            exports.create req.form, (err, user)->
                if err
                    resp.render 'register', { error:err, next:next }
                else
                    req.session.uid = req.form.uid
                    resp.redirect next

    app.get '/login', (req, resp) ->
        next = req.param('next', AFTER_LOGIN )
        if req.session.uid
            resp.redirect next
        else
            resp.render 'login', {next}

    app.post '/login', validate_login_form, (req, resp, next) ->

        nextPage = req.param('next', AFTER_LOGIN )
        if not req.form.isValid
            resp.render 'login', {error:req.form.errors.join('<br/>'), next:nextPage}
        else
            auth = passport.authenticate 'local', {
                successRedirect: nextPage,
                failureRedirect: '/login'
            }, (err, user)->
                console.log "User logged in", user
                req.session.uid = user.id
                resp.redirect nextPage

            return auth( req, resp, next )

    app.get '/logout', (req, resp)->
        req.session.destroy()
        req.logOut()
        resp.redirect '/login'

    app.get '/account', exports.force_login, (req, resp)->
        resp.render 'account', account:exports.find( req.session.uid )

    app.post '/account', exports.ensure_login, validate_account_form, (req, resp)->
        account = exports.find( req.session.uid )
        if not req.form.isValid
            resp.render 'account', {error:req.form.errors.join(' * '), account}
        else
            account.email = req.form.email
            account.save (error) -> resp.render 'account', {account,error}

    exports.reload cb
