io = require 'socket.io'

parseCookie = require('connect').utils.parseCookie

# Init socket.io request handlers

UID2SOCKET = {}

exports.log = log = console

exports.emit = (uid, msg) ->
    if uid of UID2SOCKET
        UID2SOCKET[ uid ].emit('message', msg)
    else
        log.debug "Can't push event", msg

exports.init = (app, cb)->

    sio = io.listen(app)
    
    sio.enable('browser client minification')
    sio.enable('browser client etag')
    sio.enable('browser client gzip')
    sio.set('log level', 2)
    sio.set('transports', ['websocket', 'flashsocket', 'htmlfile', 'xhr-polling', 'jsonp-polling'])

    exports.log = log = sio.log

    sio.sockets.on 'connection', (socket)->
        hs = socket.handshake
        if hs.session?.uid
            UID2SOCKET[ hs.session.uid ] = socket

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
                    accept null, true
        else
            # if there isn't, turn down the connection with a message
            # and leave the function.
            accept('No cookie transmitted.', false)

    exports.sio = sio
    cb and cb( null )
