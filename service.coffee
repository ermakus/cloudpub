fs      = require 'fs'
_       = require 'underscore'
async   = require 'async'

settings = require './settings'
queue    = require './queue'
command  = require './command'
state    = require './state'

# Default service object
exports.Service = class Service extends queue.Queue

    init: ->
        super()
        # Owner account ID
        @account = undefined
        # Instance ID service run on
        @instance = undefined
        # Application ID to run
        @app = undefined
        # Address of SSH server to run
        @address = undefined
        # Posix user to run
        @user = settings.USER
        # Service public domain
        @domain = settings.DOMAIN
        # Service public port
        @port = settings.PORT
        # Interface to bind
        @interface = "127.0.0.1"

    # Configure service and attach to groups
    configure: (params, cb)->
        exports.log.info "Configure service #{@id}:", params

        @account  = params.account or @account
        if not @account then return cb and cb(new Error("Account not set"))

        @address  = params.address or @address
        if not @address then return cb and cb(new Error("Address not set"))

        @user     = params.user or @user
        if not @user then return cb and cb(new Error("User not set"))

        @instance = params.instance or @instance
        if not @instance then return cb and cb(new Error("Instance not set"))

        @port = params.port or @port
        if not @port then return cb and cb(new Error("Port not set"))


        @app      = params.app or @app
        @home     = "/home/#{@user}/.cloudpub"

        async.series [
            (cb)=> @save(cb)
            (cb)=> @attachTo(@account,cb)
            (cb)=> @attachTo(@instance,cb)
            (cb)=> @attachTo(@app,cb)
        ], cb

    # Submit task to work queue
    submit: (params, cb)->

        if not (@address and @user)
            return cb and cb(new Error("Service not configured"))

        params.address = @address
        params.user    = @user
        
        super params, cb
    
    # Add this service to target group and subscribe it to events
    attachTo: (targetId, cb)->
        return cb and cb(null) if not targetId
        exports.log.info "Attach service to #{targetId}"
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

    # Startup handler
    startup: (cb) ->
        cb and cb(null)

    # Shutdown handler
    shutdown: (cb) ->
        cb and cb(null)

    # Install handler
    install: (cb) ->
        cb and cb(new Error("Install not implemented"))

    # Uninstall handler
    uninstall: (cb) ->
        @updateState cb

listServices = (entity, params, cb)->
    state.load params.account, (err, account)->
        return cb and cb(err) if err
        async.map account.children, state.loadWithChildren, cb

# Init request handlers here
exports.init = (app, cb)->
    return cb(null) if not app
    # List of services
    app.register 'service', listServices, ((id, entity, cb)->state.load( id, cb ))
    cb and cb(null)
