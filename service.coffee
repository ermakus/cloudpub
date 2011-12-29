fs      = require 'fs'
_       = require 'underscore'
async   = require 'async'

account  = require './account'
queue    = require './queue'
command  = require './command'
state    = require './state'

# Default service object
exports.Service = class Service extends queue.Queue

    init: ->
        super()
        # Owner account
        @account = undefined
        # Instance ID service run on
        @instance = undefined
        # Application ID to run
        @app = undefined
        # Posix user to run
        @user = undefined
        # Service domain
        @domain = account.DOMAIN
        # Service port
        @port = account.PORT

    # Submit task to work queue
    submit: (params, cb)->

        if not (@address and @user and @home and @instance)
            return cb and cb(new Error("Service not configured"))

        params.address = @address
        params.user    = @user
        params.home    = @home
        
        super params, cb
    
    # Add this service to target group and subscribe it to events
    attachTo: (targetId, cb)->
        return cb and cb(null) if not targetId
        exports.log.info "Attach service to #{targetId}"
        @mute 'state', 'serviceState', targetId
        @on 'state', 'serviceState', targetId
        async.waterfall [
            (cb)=> state.load(targetId, cb)
            (item, cb)=> item.add(@id, cb)
            (cb)=> @save(cb)
        ], cb

    # Unsubscribe target group from state events
    detachFrom: (targetId, cb)->
        return cb and cb(null) if not targetId
        @mute 'state', 'serviceState', targetId
        exports.log.info "Detach service from #{targetId}"
        async.waterfall [
            (cb)=> state.load(targetId, cb)
            (item, cb) => item.remove(@id, cb)
            (cb)=> @save(cb)
        ], cb

    # Delete service and detach from groups
    clear: (cb)->
        clear = queue.Queue.prototype.clear
        detach = (id, cb)  => @detachFrom(id, cb)
        async.forEachSeries [@app,@account,@instance], detach, (err)=>
            return cb and cb(err) if err
            clear.call @, cb

    # Configure service and attach to groups
    configure: (params, cb)->

        if not (params.address and params.user and params.instance)
            return cb and cb(new Error("Service not initialized"))

        @account  = params.account
        @address  = params.address
        @user     = params.user
        @instance = params.instance
        @app      = params.app
        @home     = "/home/#{@user}/.cloudpub/"

        async.series [
            (cb)=> @attachTo(@account,cb)
            (cb)=> @attachTo(@instance,cb)
            (cb)=> @attachTo(@app,cb)
            (cb)=> @save(cb)
        ], cb

    # Startup handler
    startup: (cb) ->
        cb and cb(new Error('Not impelemented for this service'))

    # Shutdown handler
    shutdown: (cb) ->
        cb and cb(new Error('Not impelemented for this service'))

    # Install handler
    install: (cb) ->
        cb and cb(new Error('Not impelemented for this service'))

    # Uninstall handler
    uninstall: (cb) ->
        cb and cb(new Error('Not impelemented for this service'))

# Init request handlers here
exports.init = (app, cb)->
    # List of services
    app.register 'service', ((entity, cb)->state.query('cloudpub', cb)), ((id, entity, cb)->state.load( id, cb ))
    cb and cb(null)
