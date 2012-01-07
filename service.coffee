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
        @message = "Wait..."
        # Owner account ID
        @account = undefined
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
        # Depends from. IDs of other services
        @dependsFrom = []
        # Depends to, updated automatically
        @dependsTo = []

    # Add and resolve single dependence
    addDependence: (depId, cb)->
        async.waterfall [
            # Update from
            (cb)=>
                @dependsFrom ||= []
                if depId not in @dependsFrom
                    @dependsFrom.push depId
                    @save(cb)
                else
                    cb(null)
            # Load target object
            (cb)=>
                state.load(depId, cb)
            # Update to
            (dependent, cb)=>
                dependent.dependsTo ||= []
                if @id not in dependent.dependsTo
                    dependent.dependsTo.push @id
                    dependent.save(cb)
                else
                    cb(null)
            ], cb

    # Remove dependence
    removeDependence: (depId, cb)->
        async.waterfall [
            # Update from
            (cb)=>
                if depId in @dependsFrom
                    @dependsFrom = _.without @dependsFrom, depId
                    @save(cb)
                else
                    cb(null)
            # Load target object
            (cb)=>
                state.load(depId, cb)
            # Update to
            (dependent, cb)=>
                if @id in dependent.dependentTo
                    @dependsTo = _.without @dependsTo, depId
                    dependent.dependsFrom.push @id
                    dependent.save(cb)
                else
                    cb(null)
            ], cb

    # Configure service and attach to groups
    configure: (params, cb)->
        exports.log.info "Configure service #{@id}:", params

        @account  = params.account or @account
        if not @account then return cb and cb(new Error("Account not set"))

        @address  = params.address or @address
        if not @address then return cb and cb(new Error("Address not set"))

        @user     = params.user or @user
        if not @user then return cb and cb(new Error("User not set"))

        @port = params.port or @port
        if not @port then return cb and cb(new Error("Port not set"))

        @app      = params.app or @app
        @home     = "/home/#{@user}/.cloudpub"

        async.series [
            (cb)=> @save(cb)
            (cb)=> async.forEach(@dependsFrom, ((id, cb)=>@addDependence(id,cb)), cb)
            (cb)=> @attachTo(@account,cb)
            (cb)=> @attachTo(@instance,cb)
            (cb)=> @attachTo(@app,cb)
        ], cb

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

    # Delete service and detach from others
    clear: (cb)->
        async.series [
                # Detach from listeners
                (cb)=>
                    detach = (id, cb)  => @detachFrom(id, cb)
                    async.forEach [@app,@account,@instance], detach, cb
                # Remove dependencies
                (cb)=>
                    async.forEach( @dependsFrom or [], ((id, cb)=>@removeDependence(id, cb)), cb)
                # Call super
                (cb)=>
                    queue.Queue.prototype.clear.call @, cb
            ], cb

    # Start service by ID or JSON
    start: (cb)->
        exports.log.info "Start service #{@id}"

        start = queue.Queue.prototype.start

        # Exit if already up
        if @state in ['up','maintain']
            return cb(null)

        # Start service
        async.series [
                (cb) =>
                    @stop(cb)
                (cb) =>
                    if not @isInstalled
                        @install(cb)
                    else
                        cb(null)
                (cb) =>
                    if not @isInstalled
                        @isInstalled = true
                        @save(cb)
                (cb) =>
                    @startup(cb)
                (cb) =>
                    start.call @, cb
            ], cb

    # Stop service
    stop: (cb)->
        exports.log.info "Stop service #{@id}"
        
        stop  = queue.Queue.prototype.stop
        start = queue.Queue.prototype.start
        
        if @state in ['down','maintain','error']
            return cb(null)

        ifUninstall = (cb)=>
            if @doUninstall and @isInstalled
                @uninstall (err)=>
                    return cb(err) if err
                    @isInstalled = false
                    @save(cb)
            else
                cb(null)

        async.series [
            (cb) => stop.call(@, cb)
            (cb) => @shutdown(cb)
            (cb) => ifUninstall(cb)
            (cb) => start.call(@, cb)
        ], cb

    # Startup handler
    startup: (cb) ->
        cb and cb(new Error("Service: Startup not implemented"))

    # Shutdown handler
    shutdown: (cb) ->
        cb and cb(null)

    # Install handler
    install: (cb) ->
        cb and cb(new Error("Service: Install not implemented"))

    # Uninstall handler
    uninstall: (cb) ->
        @updateState cb

# Take servers from account
listServices = (entity, params, cb)->
    state.load params.account, (err, account)->
        return cb and cb(err) if err
        async.map account.children, state.loadWithChildren, cb

# Init request handlers here
exports.init = (app, cb)->
    return cb(null) if not app
    # List of services
    app.register 'service', listServices
    cb and cb(null)
