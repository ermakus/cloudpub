_ = require 'underscore'
async = require 'async'
state = require './state'
settings = require './settings'
account = require './account'


# Base class for all commands
exports.Command = class Command extends state.State

    # Start executing of command
    start: (cb)->
        cb(null)

    # Interrupt command
    stop: (cb)->
        cb(null)

# print helper
hr = (symbol)->
    for i in [0..6]
        symbol = symbol+symbol
    symbol + "\n"

#
# Main ClodFu command handler
#
exports.Cloudfu = class extends Command

    init: ->
        super()
        @stdout = exports.log.stdout

    # Command handlers
    # No help yet
    help: (params, cb)->
        @stdout "Use the source, " + settings.USER
        @stdout "Look at #{__filename} for available commands"
        cb( new Error("Help not implemented" ) )

    # Query object storage
    query: (params, cb)->
        state.query params.arg0 or '*', params, (err, states)=>
            return cb(err) if err
            count = 0
            @stdout hr('-')
            @stdout "Object Index:\n"
            @stdout hr('-')
            for obj in states
                @stdout "\##{obj.id}\t#{obj.package}.#{obj.entity}\t[#{obj.state}]\t#{obj.message}\n"
                count += 1
            @stdout hr('-')
            @stdout "Total: #{count} object(s)\n"
            @stdout hr('-')
            cb(null)

    # Get object by ID
    get: (params, cb)->
        state.load params.arg0, params, (err, obj)=>
            return cb(err) if err
            count = 0
            @stdout hr('-')
            @stdout JSON.stringify obj
            @stdout hr('-')
            cb(null)

    # Run test suite
    test: (params, cb)->
        async.waterfall [
            (cb) -> state.create('test/SUITE', 'suite', cb)
            (suite, cb)->
                suite.createTests [
                        'core'
                        'instanceStart'
                        'appStart'
                        'appStop'
                        'instanceStop'
                ], (err)-> cb( err, suite )
            (suite, cb) -> suite.start(cb)
        ], (err)-> cb( err, true )

    # Just print params
    params: (params, cb)->
        for key of params
            @stdout "#{key}=#{params[key]}"
        cb(null)

    # Startup service
    startup: (params, cb)->
        state.load params.arg0, (err, obj)=>
            return cb(err) if err
            obj.startup params, cb

    # Shutdown service
    shutdown: (params, cb)->
        state.load params.arg0, (err, obj)=>
            return cb(err) if err
            obj.shutdown params, cb

#
# Command line parser
# Entry point for bin/kya
#
exports.kya = (command, params, cb)->
    exports.log.debug "Command #{command.join(' ')}"
    if command.length < 1
        cb( new Error("No command specified") )
    # First is method name
    # Other args is pass as params arg0..argN
    method = undefined
    argIndex = 0
    for arg in command
        if arg[0] == '-'
            continue
        if not method
            method = arg
            continue
        params["arg#{argIndex}"] = arg
        argIndex++

    # Create Cloudfu object
    state.create null, 'cloudfu', (err, state)->
        return cb( err ) if err
        # Run method with params
        if method of state
            state[method] params, cb
        else
            cb( new Error("Method #{method} not supported") )

# List all sessions for current user
listSessions = (entity, params, cb)->
    # Load account and instancies
    state.query 'session', cb

# Init HTTP request handlers
exports.init = (app, cb)->
    return cb(null) if not app
    app.register 'cloudfu', listSessions
    app.post '/kya', account.ensure_login, (req, resp)->
        req.params.account = req.session.uid
        exports.kya req.param('command').split(" "), req.params, (err)->
            if err
                resp.send err.message, 500
            else
                resp.send true
    cb(null)
