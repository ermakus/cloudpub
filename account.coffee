form     = require 'express-form'
hasher   = require 'password-hash'
passport = require 'passport'
crypto   = require 'crypto'
state    = require './state'

LocalStrategy  = require('passport-local').Strategy
GoogleStrategy = require('passport-google').Strategy

FORCE_USER=false
AFTER_LOGIN='/app'
USER_PREFIX='user-'

exports.Account = class Account extends state.State

sha1 = (text)->
    h = crypto.createHash 'sha1'
    h.update text
    return h.digest 'hex'

authorize = (username, password, done) ->
    state.load USER_PREFIX + username, (err, user)->
        if err or not hasher.verify(password, user.password)
            exports.log.error "Auth of #{username} failed"
            return done(null, false)
        else
            exports.log.info "Auth of #{username} succeed"
            return done(null, user)

google_authorize = (userid, profile, done) ->
    userid = sha1 userid
    state.loadOrCreate USER_PREFIX + userid, 'account', (err, user)->
        user.email = profile.emails[0].value
        user.login = profile.displayName
        user.save (err)->
            done(err, user)

passport.use new LocalStrategy({ usernameField: 'uid', passwordField: 'password'}, authorize )

passport.use new GoogleStrategy({
    returnURL: 'http://localhost:3000/google/done',
    realm: 'http://localhost:3000/'}, google_authorize )


passport.serializeUser (user, done)->
    user.save done

passport.deserializeUser (id, done)->
    state.load USER_PREFIX + id, done

exports.ensure_login = (req, resp, next) ->
    req.session.uid ?= FORCE_USER
    if req.session.uid
        next()
    else
        next( new Error('User not authorized') )

exports.force_login = (req, resp, next) ->
    req.session.uid ?= FORCE_USER
    if req.session.uid
        next()
    else
        resp.redirect '/login?next=' + req.path

# Init view and user cache
exports.init = (app, cb)->

    validate_uid_form = form(
        form.filter("uid").trim().toLower(),
        form.validate("uid").required().is(/^[a-z0-9_]+$/)
    )

    validate_register_form = form(
        form.filter("uid").trim().toLower(),
        form.validate("uid").required().is(/^[a-z0-9_]+$/),
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

    app.get '/register', (req, resp) ->
        next = req.param('next', AFTER_LOGIN )
        resp.render 'register', {next}


    app.get '/validate/uid', validate_uid_form, (req, resp) ->
        if not req.form.isValid
            return resp.send( JSON.strngify req.form.errors.join("\n") )
        else
            state.load USER_PREFIX + req.form.uid, (err, user)->
                if not err
                    resp.send JSON.stringify "Account already exist"
                else
                    resp.send JSON.stringify true

    app.post '/register', validate_register_form, (req, resp) ->
        next = req.param('next', AFTER_LOGIN)
        if not req.form.isValid
            resp.render 'register', { error:req.form.errors.join('\n'), next }
        else
            state.load USER_PREFIX + req.form.uid, (err, user)->
                if not err
                    return resp.send "Account already exist"
                else
                    state.create USER_PREFIX + req.form.uid, "account", (err, account)->
                        if err
                            resp.render 'register', { error:err, next:next }
                        else
                            req.session.uid  = account.id
                            req.session.login = account.login
                            account.login    = req.form.uid
                            account.password = hasher.generate req.form.password
                            account.email = req.form.email
                            account.save (err)->
                                resp.redirect next

    app.get '/login', (req, resp) ->
        next = req.param('next', AFTER_LOGIN )
        req.session.next = next
        if req.session.uid
            resp.redirect next
        else
            resp.render 'login', {next}

    app.post '/login', validate_login_form, (req, resp, next) ->

        nextPage = req.param('next', AFTER_LOGIN )
        if not req.form.isValid
            resp.render 'login', {error:req.form.errors.join("\n"), next:nextPage}
        else
            auth = passport.authenticate 'local', {
                successRedirect: nextPage,
                failureRedirect: '/login'
            }, (err, user)->
                return next(err) if err
                if not user
                    return resp.render 'login', {error:"Invalid user name or password"}
                req.session.uid = user.id
                req.session.login = user.login
                resp.redirect nextPage

            return auth( req, resp, next )

    app.get '/logout', (req, resp)->
        req.session.destroy()
        req.logOut()
        resp.redirect '/login'

    app.get '/account', exports.force_login, (req, resp)->
        state.load req.session.uid, (error, account)->
            resp.render 'account', {account, error}

    app.post '/account', exports.ensure_login, validate_account_form, (req, resp)->
        state.load req.session.uid, (error, account)->
            if error then return resp.render 'account', {error}
            if not req.form.isValid
                resp.render 'account', {error:req.form.errors.join(' * '), account}
            else
                if req.form.password
                    account.password = hasher.generate req.form.password
                account.email = req.form.email
                account.save (error) -> resp.render 'account', {account,error}

    app.get '/google/login', passport.authenticate('google')

    app.get '/google/done', (req, resp, next)->
        auth = passport.authenticate('google', {}, (err, user)->
            return next(err) if err
            if not user
                return resp.render 'login', {error:"Google account error"}
            req.session.uid = user.id
            req.session.login = user.login
            resp.redirect req.session?.next or AFTER_LOGIN
        )
        auth req, resp, next

    cb and cb(null)
