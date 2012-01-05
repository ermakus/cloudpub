io          = require 'socket.io'
_           = require 'underscore'
async       = require 'async'
parseCookie = require('connect').utils.parseCookie
ioClient    = require('./patched_modules/socket.io-client')
settings    = require './settings'
state       = require './state'

# Socket.io messaging facility

defaultCallback = ->

# Emit event by account ID
exports.emit = (accountId, msg, cb=defaultCallback) ->
    state.query 'session', account:accountId, (err, sessions)->
        return cb(err) if err
        for session in sessions
            # Query not implemented, so filter brute force
            if session.sessionData?.uid != accountId then continue
            for client in exports.sio.sockets.clients()
                if client.id in session.sockets
                    exports.log.info "Send message to socket ", client.id
                    client.emit('message', msg)

# Init module
exports.init = (app, cb)->

    # If master is set, connect to it
    if settings.MASTER
        exports.log.info "Connecting to master domain: #{settings.MASTER}"
        socket = ioClient.connect("http://#{settings.MASTER}:#{settings.MASTER_PORT}", {
                transports:['websocket']
        })
        socket.on 'connect', ->
            exports.log.info "Connected to master: #{settings.MASTER}"
        socket.on 'disconnect', ->
            exports.log.warn "Disconnected from master: #{settings.MASTER}"
        socket.on 'error', (err) ->
            exports.log.error "Master connection error: #{err}"
        socket.send JSON.stringify { state:"up", message:"Connected to master" }
    
    # End here if not server
    return cb(null) if not app

    # COnfigure socket.io
    sio = io.listen(app)
    
    sio.enable('browser client minification')
    sio.enable('browser client etag')
    sio.enable('browser client gzip')
    sio.set('log level', 1)
    sio.set('transports', ['websocket', 'flashsocket', 'htmlfile', 'xhr-polling', 'jsonp-polling'])

    # Handle incoming connection
    sio.sockets.on 'connection', (socket)->
        hs = socket.handshake
        # We maintain socket ID list as session field
        if hs.session
            # Add socket IDs to list
            hs.session.sockets ||= []
            hs.session.sockets.push socket.id
            hs.session.save (err)->
                if err then exports.log.error "Attach socket error", err

        socket.on 'disconnect', ->
            # Remove socket ID from list
            if hs.session
                hs.session.sockets = _.without hs.session.sockets, socket.id
                hs.session.save (err)->
                    if err then exports.log.error "Detach socket error", err
                    hs.session = undefined

        # TODO Handle incoming message
        socket.on 'message', (msg) ->
            exports.log.info "Socket message: ", msg


    sio.set 'authorization', (data, accept) ->
        # check if there's a cookie header
        if data.headers.cookie
            # if there is, parse the cookie
            data.cookie = parseCookie(data.headers.cookie)
            # note that you will need to use the same key to grad the
            # session id, as you specified in the Express setup.
            sessionID = data.cookie['cloudpub.sid']
            # Load session from storage
            state.load  sessionID, (err, session)->
                if err or not session
                    accept err and err.message, false
                else
                    data.session = session
                    exports.log.info "User connection accepted"
                    accept null, true
        else
            # if there isn't, probably it slave server
            # Accept connection and wait for messages
            exports.log.info "Server connection accepted"
            accept null, true
            #accept('No cookie transmitted.', false)

    exports.sio = sio

    # Clear all sockets from sessions
    state.query 'session', (err, sessions)->
        return cb(err) if err
        async.forEach sessions, ((session,cb)->session.sockets=[]; session.save(cb)), cb
