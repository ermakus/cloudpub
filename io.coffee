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
            if session.http?.uid != accountId then continue
            for client in exports.sio.sockets.clients()
                if client.id in session.sockets
                    exports.log.info "Send message to socket ", client.id
                    client.emit('message', msg)


# Emit event to master
exports.emitMaster = emitMaster = (event)->
    exports.log.info "Send event to master", event
    exports.cio.send JSON.stringify(event)


# Init socket.io listener
initListener = (app)->
    # Configure socket.io
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
                if hs.session.clearOnDisconnect
                    exports.log.info "Clear socket session", hs.session.id
                    hs.session.clear (err)->
                        if err then exports.log.error "Clear socket session error", err
                        hs.session = undefined
                else
                    exports.log.info "Detach socket from session", hs.session.id
                    hs.session.save (err)->
                        if err then exports.log.error "Detach socket error", err
                        hs.session = undefined

        # Handle incoming message
        socket.on 'message', (msg) ->
            try
                msg = JSON.parse msg
            catch e
                msg = undefined

            if hs.session
                exports.log.info "Message", msg
                hs.session.emit 'message', msg, (err)->
                    if err then exports.log.error "Message handler error". err
            else
                exports.log.error "Message to unknown session", msg
                

    sio.set 'authorization', (data, accept) ->
        # check if there's a cookie header
        if data.headers.cookie
            # if there is, parse the cookie
            data.cookie = parseCookie(data.headers.cookie)
            # note that you will need to use the same key to grad the
            # session id, as you specified in the Express setup.
            sessionID = data.cookie['cloudpub.sid']
            getSession = state.load
        else
            # If no cookie, create server session
            sessionID = {entity:'session',clearOnDisconnect:true}
            getSession = state.create

        # Load session from storage
        getSession sessionID, (err, session)->
            if not session.expired
                session.setLifetime 5000
            if err or not session
                exports.log.error "Session not found", err
                accept err and err.message, false
            else
                data.session = session
                exports.log.info "Socket connected to session", session.id
                accept null, true

    return sio

# Init socket.io client (if MASTER specified)
initSender = (cb)->
    exports.log.info "Connecting to master", settings.MASTER
    socket = ioClient.connect("http://#{settings.MASTER}:#{settings.MASTER_PORT}", {
            'transports'             : ['websocket']
            'try multiple transports': false
            'connect timeout'        : 1000
    })
    socket.once 'connect', ->
        exports.log.info "Connected to master", settings.MASTER
        cb( null, socket )

    socket.on 'disconnect', ->
        exports.log.warn "Disconnected from master", settings.MASTER
    
    socket.once 'connect_failed', (err) ->
        cb( new Error("Master connection error"), socket )
    return socket


clearSockets = (cb)->
    # Clear all sockets from sessions
    state.query 'session', (err, sessions)->
        return cb(err) if err
        async.forEach sessions, ((session,cb)->session.sockets=[]; session.save(cb)), cb

# Init module
exports.init = (app, cb)->
    # if server, init listener
    if app
        exports.sio = initListener(app)

    # If master is set, connect to it
    if settings.MASTER
        initSender (err, socket)->
            return cb(err) if (err)
            exports.cio = socket
            emitMaster( id:settings.ID, state:"up", message:"Slave Connected" )
            clearSockets cb
    else
        clearSockets cb


# Stop module
exports.stop = (cb)->

    if exports.cio
        exports.log.debug "Socket.io client disconnected"
        exports.cio.disconnect()

    if exports.sio
        exports.log.debug "Socket.io server disconnected"
        exports.sio.disconnect()

    cb(null)
