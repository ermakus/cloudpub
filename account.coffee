_        = require 'underscore'
form     = require 'express-form'
hasher   = require 'password-hash'
passport = require 'passport'
crypto   = require 'crypto'
nconf    = require 'nconf'
settings = require './settings'
io       = require './io'
state    = require './state'
group    = require './group'

LocalStrategy  = require('passport-local').Strategy
GoogleStrategy = require('passport-google').Strategy

FORCE_USER=false
AFTER_LOGIN='/app'
USER_PREFIX='user-'

exports.log = console

# User account class
# Children is services
exports.Account = class Account extends group.Group

    init: ->
        super()
        # User display name
        @name = undefined
        # User E-Mail
        @email = undefined
        # Salted hashed password
        @password = undefined
        # Authorization provider
        @provider = 'local'

    # Service state change handler
    serviceState: (event, cb)->
        exports.log.info 'Account event'
        io.emit @id, {state:event.state, message:event.message}
        cb and cb(null)

# SHA1 helper function
exports.sha1 = sha1 = (text)->
    h = crypto.createHash 'sha1'
    h.update text
    return h.digest 'hex'

# Authorize user with local account
authorize = (username, password, done) ->
    state.load USER_PREFIX + username, (err, user)->
        if err or not hasher.verify(password, user.password)
            exports.log.error "Auth of #{username} failed"
            return done(null, false)
        else
            exports.log.info "Auth of #{username} succeed"
            return done(null, user)

# Authorize user with Google
google_authorize = (userid, profile, done) ->
    email = profile.emails[0].value
    state.loadOrCreate USER_PREFIX + email, 'account', (err, user)->
        user.provider = 'google'
        user.email = email
        user.name  = profile.displayName
        user.save (err)->
            done(err, user)

# Local auth strategy
passport.use new LocalStrategy({ usernameField: 'email', passwordField: 'password'}, authorize )

# Google auth strategy
passport.use new GoogleStrategy({
    returnURL: "http://#{settings.DOMAIN}:#{settings.PORT}/google/done",
    realm: "http://#{settings.DOMAIN}:#{settings.PORT}/"}, google_authorize )

# User serialize callback
passport.serializeUser (user, done)->
    user.save done

# User deserialize callback
passport.deserializeUser (id, done)->
    state.load USER_PREFIX + id, done

# Middleware to block unauthorized user
exports.ensure_login = (req, resp, next) ->
    req.session.uid ?= FORCE_USER
    if req.session.uid
        next()
    else
        next( new Error('User not authorized') )

# Middleware to redirect unauthorized user to login page
exports.force_login = (req, resp, next) ->
    req.session.uid ?= FORCE_USER
    if req.session.uid
        next()
    else
        resp.redirect '/login?next=' + req.path

# Init module views
exports.init = (app, cb)->
    return cb(null) if not app

    validate_account_form = form(
        form.filter("email").trim(),
        form.validate("email").required().isEmail(),
        form.validate("password")
    )

    # Register page
    app.get '/register', (req, resp) ->
        next = req.param('next', AFTER_LOGIN )
        resp.render 'register', {next}

    # Validate login
    app.get '/validate/uid', (req, resp) ->
        state.load USER_PREFIX + req.form.uid, (err, user)->
            if not err
                resp.send JSON.stringify "Account already exist"
            else
                resp.send JSON.stringify true

    # Register handler
    app.post '/register', validate_account_form, (req, resp) ->
        next = req.param('next', AFTER_LOGIN)
        if not req.form.isValid
            resp.render 'register', { error:req.form.errors.join('\n'), next }
        else
            state.load USER_PREFIX + req.form.email, (err, user)->
                if not err
                    return resp.send "Account already exist"
                else
                    state.create USER_PREFIX + req.form.email, "account", (err, account)->
                        if err
                            resp.render 'register', { error:err, next:next }
                        else
                            req.session.uid  = account.id
                            account.email    = req.form.email
                            account.password = hasher.generate req.form.password
                            account.save (err)->
                                resp.redirect next

    # Login page
    app.get '/login', (req, resp) ->
        next = req.param('next', AFTER_LOGIN )
        req.session.next = next
        if req.session.uid
            resp.redirect next
        else
            resp.render 'login', {next}

    # Login handler
    app.post '/login', validate_account_form, (req, resp, next) ->

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
                resp.redirect nextPage

            return auth( req, resp, next )

    # Logout handler
    app.get '/logout', (req, resp)->
        req.session.destroy()
        req.logOut()
        resp.redirect '/login'

    # Edit account form
    app.get '/account', exports.force_login, (req, resp)->
        state.load req.session.uid, (error, account)->
            resp.render 'account', {account, error}

    # Edit account handler
    app.post '/account', exports.ensure_login, (req, resp)->
        state.load req.session.uid, (error, account)->
            if error then return resp.render 'account', {error}
            if not _.isEmpty( req.param('password') )
                account.password = hasher.generate req.param('password')
            account.save (error) ->
                resp.render 'account', {account,error}

    # Google authorization
    app.get '/google/login', passport.authenticate('google')

    app.get '/google/done', (req, resp, next)->
        auth = passport.authenticate('google', {}, (err, user)->
            return next(err) if err
            if not user
                return resp.render 'login', {error:"Google account error"}
            req.session.uid = user.id
            resp.redirect req.session?.next or AFTER_LOGIN
        )
        auth req, resp, next

    cb and cb(null)
