_       = require 'underscore'
async   = require 'async'
express = require 'express'
state   = require './state'

defaultCallback = ->

# Session object as base for all sessions
exports.Session = class Session extends state.State

    # Clear session if expired
    clearIfExpired: (cb)->
        if typeof(@expires) == 'string'
            expires = new Date(@expires)
        else
            expires = @expires

        if (expires and (Date.now() > expires.getTime()))
            exports.log.warn "Session #{@id} is expired: ", expires
            @clear cb
        else
            cb(null)


# Express session store implementation on top of our state store
exports.SessionStore = class SessionStore extends express.session.Store

    constructor: (options) ->
        setInterval (=> @clearExpired( defaultCallback ) ), 60000
        
    get: (sid, cb = defaultCallback) ->
        state.load "session-" + sid, 'session', (err, session)->
            return cb() if err
            cb( null, session.sessionData )
    
    set: (sid, data, cb = defaultCallback) ->
        state.loadOrCreate "session-" + sid, 'session', (err, session)=>
            return cb(err) if err
            if data && data.cookie && data.cookie.originalMaxAge
                @expires = new Date( Date.now() + data.cookie.originalMaxAge)
            else
                exports.log.error "Session cookie not set"
            session.sessionData = data
            session.save cb
    
    destroy: (sid, cb = defaultCallback) ->
        state.load "session-" + sid, 'session', (err, session)->
            return cb(null) if err
            session.clear cb
    
    all: (cb = defaultCallback) ->
        state.query 'session', (err, sessions)->
            return cb and cb(err) if err
            cb null, (session.id for session in sessions)
    
    clearExpired: (cb = defaultCallback) ->
        state.query 'session', (err, sessions)->
            return cb and cb(err) if err
            async.forEach sessions, ((session, cb)->session.clearIfExpired(cb)), cb

    clear: (cb = defaultCallback) ->
        state.query 'session', (err, sessions)->
            return cb and cb(err) if err
            async.forEach sessions, ((session, cb) -> session.clear cb), cb
        
    length: (cb = defaultCallback) ->
        state.query 'session', (err, sessions)->
            return cb and cb(err) if err
            cb null, sessions.length

