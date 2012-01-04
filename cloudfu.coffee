_ = require 'underscore'
async = require 'async'
state = require './state'
settings = require './settings'

# Base class for all commands
exports.Command = class Command extends state.State

    # Start executing of command
    start: (cb)->
        cb(null)

    # Interrupt command
    stop: (cb)->
        cb(null)

exports.Help = class extends Command

    startup: (params, cb)->
        exports.log.info "Use the source, " + settings.USER
        exports.log.info "view #{__filename}"
        cb( new Error("Help not implemented" ) )


# Command handler object
exports.Cloudfu = class extends Command

    execOn: (instanceId, cb)->
        exports.log.info "Run #{@command} on #{instanceId}"
        state.load instanceId, (err, instance)=>
            return cb(err) if err
            instance.submit {
                entity:@command[0],
                command:@command[1...]
            }, cb

    # Run command on instance
    startup: (params, cb)->
        params.instance ||= []
        # Single checkbox passed as string, so make it array
        if _.isString(params.instance)
            params.instance = [params.instance]
        @instancies = params.instance
        if _.isEmpty(@instancies)
            return cb and cb(new Error("Instancies not selected"))

        @command = params.command
        if _.isEmpty(@command)
            return cb(new Error("Empty command"))
        @command = @command.split(' ')
        async.forEach @instancies, ((instance, cb)=> @execOn(instance,cb)), cb

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
    app.register 'cloudfu', listCommands, getCommand
    cb(null)
