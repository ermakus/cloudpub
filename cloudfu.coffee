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

#
# Main ClodFu command handler
# Singleton TBD
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

    # Show local object cache
    list: (params, cb)->
        hr = (symbol)->
            for i in [0..6]
                symbol = symbol+symbol
            symbol + "\n"

        state.query params.arg0 or 'service', (err, states)=>
            return cb(err) if err
            count = 0
            @stdout hr('-')
            @stdout "CACHE:\n"
            @stdout hr('-')
            for obj in states
                @stdout "\##{obj.id}\t#{obj.package}.#{obj.entity}\t[#{obj.state}]\t#{obj.message}\n"
                count += 1
            @stdout hr('-')
            @stdout "Total: #{count} object(s)\n"
            @stdout hr('-')
            cb(null)

    # Run test suite
    test: (params, cb)->
        async.waterfall [
            (cb) -> state.create('test-suite', 'suite', cb)
            (suite, cb)->
                suite.submitTests [
                        'state'
                        'instanceStart'
#                        'appStart'
#                        'appStop'
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
    exports.log.info "Command #{command.join(' ')}"
    if command.length < 1
        cb( new Error("Command too short") )
    # First is method name
    method = command[0]
    # Second is object ID or default Cloudfu handler
    id = command[1] or "cloudfu"
    # Other args is pass to params as arg0..argN keys
    args = command[1...]
    argIndex = 0
    for arg in args
        params["arg#{argIndex}"] = arg
    # Load or create object
    state.loadOrCreate id, 'cloudfu', (err, state)->
        return cb( err ) if err
        # Run method with params
        if method of state
            state[method] params, cb
        else
            cb( new Error("Method #{method} not supported") )

# Get list of all executing commands of account
listCommands = (entity, params, cb)->

    commands = []

    # Get service commands
    getCommands = (service, cb)->
        service.resolve (err)->
            cb(err) if err
            for worker in service._children
                commands.push worker
            cb( null )

    async.waterfall [
        # Load account
        (cb) ->
            state.load params.account, cb
        # Load services
        (account, cb)->
            async.map account.children, state.loadWithChildren, cb
        # Collect commands from services
        (services, cb)->
            async.forEach services, getCommands, cb
    ], (err)-> cb(err, commands)


# Return command handler
getCommand = (id, entity, cb)->
    exports.log.info "Execute command: ", id
    state.loadOrCreate id, 'cloudfu', cb

# Init module
exports.init = (app, cb)->
    return cb(null) if not app
    app.register 'cloudfu', listCommands, getCommand
    app.post '/kya', account.ensure_login, (req, resp)->
        req.params.account = req.session.uid
        exports.kya req.param('command').split(" "), req.params, (err)->
            if err
                resp.send err.message, 500
            else
                resp.send true

    cb(null)
