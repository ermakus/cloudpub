settings = require './settings'
io = require 'socket.io'
ioClient = require('./patched_modules/socket.io-client')
        
parseCookie = require('connect').utils.parseCookie

# Init socket.io request handlers

UID2SOCKET = {}

exports.emit = (uid, msg) ->
    if uid of UID2SOCKET
        UID2SOCKET[ uid ].emit('message', msg)
    else
        exports.log.debug "Can't push event", msg

exports.init = (app, cb)->

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

    return cb(null) if not app

    sio = io.listen(app)
    
    sio.enable('browser client minification')
    sio.enable('browser client etag')
    sio.enable('browser client gzip')
    sio.set('log level', 1)
    sio.set('transports', ['websocket', 'flashsocket', 'htmlfile', 'xhr-polling', 'jsonp-polling'])

    sio.sockets.on 'connection', (socket)->
        hs = socket.handshake
        if hs.session?.uid
            UID2SOCKET[ hs.session.uid ] = socket

        socket.on 'message', (msg) ->
            exports.log.info "Socket message: ", msg

        socket.on 'disconnect', ->
            if hs.session?.uid
                delete UID2SOCKET[ hs.session.uid ]

    sio.set 'authorization', (data, accept) ->
        # check if there's a cookie header
        if data.headers.cookie
            # if there is, parse the cookie
            data.cookie = parseCookie(data.headers.cookie)
            # note that you will need to use the same key to grad the
            # session id, as you specified in the Express setup.
            data.sessionID = data.cookie['cloudpub.sid']
            app.sessionStore.get  data.sessionID, (err, session)->
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
    cb( null )

