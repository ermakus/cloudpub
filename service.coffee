fs      = require 'fs'
_       = require 'underscore'
async   = require 'async'

settings = require './settings'
queue    = require './queue'
command  = require './command'
state    = require './state'
sugar    = require './sugar'

#
# Service object
#

exports.Service = class Service extends queue.Queue

    init: ->
        super()
        # State, one of 'up', 'down', 'maintain'
        @state = 'down'
        # Service goal (start or stop)
        @goal = undefined
        # Default message
        @message = 'waiting'
        # Owner account ID
        @account = undefined
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
        # Depends from services
        @depends = []

    # Add and resolve single dependence
    addDependence: (depId, cb)->
        sugar.relate( "depends", @id, depId, cb)

    # Remove dependence
    removeDependence: (depId, cb)->
        # Ignore non-existend references
        sugar.unrelate( "depends", @id, depId, ((err)->cb(null)))


    # Configure service and attach to groups
    configure: (params, cb)->
        exports.log.info "Configure service",  @id, params

        config = (name)=>
            if name of params
                @[name] = params[name]
            if not @[name]
                throw new Error("Service param #{name} not set")

        if params
            try
                config "account"
                config "address"
                config "user"
                config "port"
            catch err
                return cb(err)
 
        # Init home 
        @home = "/home/#{@user}/.cloudpub"
        @doUninstall = (params and params.doUninstall) or @doUninstall

        # Configure service
        async.waterfall [
            # Save config
            (cb)=> @save(cb)
            # Resolve dependencies
            (cb)=> async.forEach(@depends, ((id, cb)=>@addDependence(id,cb)), cb)
        ], cb

    # Delete service and detach from others
    clear: (cb)->
        async.series [
                # Remove dependencies
                (cb)=>
                    async.forEach( @depends or [], ((id, cb)=>@removeDependence(id, cb)), cb)
                # Call super
                (cb)=>
                    queue.Queue.prototype.clear.call @, cb
            ], cb

    # Start service
    start: (params,cb)->
        if typeof(params)=='function'
            cb = params
            params = undefined

        exports.log.info "Service start", @id
        if @state == 'up'
            exports.log.warn "Service already started"
            return cb(null)
        @goal = "start"
        @state = "maintain"
        # On start handler
        @configure params, (err) =>
            return cb(err) if err
            @emit 'starting', @, cb


    # Default 'starting' event handler
    starting: (event, cb)->
        exports.log.info "Service starting", @id

        # Start service
        # Called @install and @startup internally
        async.waterfall [
                # Check dependencies
                (cb) =>
                    sugar.groupState( @depends, cb )
                # If dependecies not ready, break waterfall
                (state, cb)=>
                    state ||= 'up'
                    if state != 'up'
                        exports.log.warn "Start dependencies first", @depends
                        cb("BREAK")
                    else
                        cb(null)
                # Clear queue
                (cb) =>
                    queue.Queue.prototype.stop.call( @, cb )
                # Fill queue by install commands 
                (cb) =>
                    if not @isInstalled
                        @install(cb)
                    else
                        cb(null)
                # Fill queue by startup commands
                (cb) =>
                    @startup(cb)
                # Start queue
                (cb) =>
                    queue.Queue.prototype.start.call( @, cb )
            ], (err)->
                # Handle break
                if err == "BREAK" then return cb(null)
                cb(err)

    # Service started event
    started: (event, cb)->
        exports.log.info "Service started", @id
        @state = 'up'
        @goal  = undefined
        @isInstalled = true
        @save(cb)

    # Stop service
    stop: (params,cb)->
        exports.log.info "Service stop", @id
        if typeof(params)=='function'
            cb = params
            params = undefined
        if @state == 'down'
            exports.log.warn "Service already stopped", @state
            return cb(null)
        @goal = "stop"
        @state = "maintain"
        # On start handler
        @configure params, (err) =>
            return cb(err) if err
            @emit 'stopping', @, cb


    # Stop service
    stopping: (params, cb)->
        exports.log.info "Service stopping", @id, @state

        ifUninstall = (cb)=>
            if @doUninstall
                exports.log.info "Service uninstalling", @id
                @uninstall (err)=>
                    return cb(err) if err
                    @isInstalled = false
                    @save(cb)
            else
                cb(null)

        # Stop service
        async.waterfall [
                # Check dependencies
                (cb) =>
                    sugar.groupState( @_depends, cb )
                # If dependecies not ready, break waterfall
                (state, cb)=>
                    state ||= 'down'
                    if state != 'down'
                        exports.log.warn "Service dependencies is running", @_depends
                        cb("BREAK")
                    else
                        cb(null)
                # Clear queue
                (cb) =>
                    queue.Queue.prototype.stop.call( @, cb )
                # Submit shutdown job
                (cb) =>
                    @shutdown(cb)
                # Submit uninstall job
                (cb) =>
                    ifUninstall(cb)
                # Start queue
                (cb) =>
                    queue.Queue.prototype.start.call( @, params, cb)
            ], (err)->
                if err == "BREAK" then cb(null)
                cb(err)

    # Service stopped event
    stopped: (event, cb)->
        exports.log.info "Service stopped", @id
        @state = 'down'
        @goal  = undefined
        @save(cb)

    # Queue success event
    success: (event, cb)->
        if @goal == 'start'
            return @emit 'started', event, cb
        if @goal == 'stop'
            return @emit 'stopped', event, cb
        cb(null)


    # Dependent services state event handler
    serviceState: (event, cb)->
        exports.log.info "Service state event", event
        cb(null)

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
        cb and cb(null)

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
