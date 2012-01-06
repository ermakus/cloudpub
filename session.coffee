_        = require 'underscore'
async    = require 'async'
express  = require 'express'
settings = require './settings'
state    = require './state'

# Session object as base for all sessions
exports.Session = class Session extends state.State

    # Set time before garbage collected
    setLifetime: (ms)->
        @expires = Date.now() + ms


    # Clear session if expired
    clearIfExpired: (cb)->
        if typeof(@expires) == 'string'
            expires = new Date(@expires).getTime()
        else
            expires = @expires

        if (expires and (Date.now() > expires))
            exports.log.warn "Session #{@id} is expired: ", expires
            @clear cb
        else
            cb(null)

# Default callback
defaultCallback = (err)->
    if err then exports.log.error "SessionStore error", err

# Express session store implementation on top of our state store
exports.SessionStore = class SessionStore extends express.session.Store

    constructor: (options) ->
        
    get: (sid, cb = defaultCallback) ->
        state.load sid, 'session', (err, session)->
            return cb() if err
            cb( null, session.http )
    
    set: (sid, data, cb = defaultCallback) ->
        state.loadOrCreate sid, 'session', (err, session)=>
            return cb(err) if err
            if data && data.cookie && data.cookie.originalMaxAge
                session.setLifetime data.cookie.originalMaxAge
            else
                exports.log.error "Session cookie not set"
                session.setLifetime( 60000 )
            session.state = 'up'
            session.message = "User: " + data.uid
            session.http = data
            session.save cb
    
    destroy: (sid, cb = defaultCallback) ->
        state.load sid, (err, session)->
            return cb(null) if err
            session.clear cb
    
    all: (cb = defaultCallback) ->
        state.query 'session', (err, sessions)->
            return cb and cb(err) if err
            cb null, (session.id for session in sessions)
    
    clear: (cb = defaultCallback) ->
        state.query 'session', (err, sessions)->
            return cb and cb(err) if err
            async.forEach sessions, ((session, cb) -> session.clear cb), cb
        
    length: (cb = defaultCallback) ->
        state.query 'session', (err, sessions)->
            return cb and cb(err) if err
            cb null, sessions.length

# GC internals
gcInterval=undefined
gcCallback=(err)->
    if err then exports.log.error "Garbage collector error", err

# Collect garbage
exports.gc = (cb=gcCallback)->
    state.query 'session', (err, sessions)->
        return cb and cb(err) if err
        async.forEach sessions, ((session, cb)->session.clearIfExpired(cb)), cb

# Init module
exports.init = (app, cb)->
    return cb(null) if not app
    interval = settings.GC_INTERVAL
    exports.log.debug "Garbage collector interval", interval
    gcInterval = setInterval( exports.gc, interval )
    cb(null)

# Stop module
exports.stop = (cb)->
    if gcInterval
        clearInterval gcInterval
    cb(null)
