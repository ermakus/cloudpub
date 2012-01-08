fs      = require 'fs'
_       = require 'underscore'
async   = require 'async'

settings = require './settings'
queue    = require './queue'
command  = require './command'
state    = require './state'
sugar    = require './sugar'

# Service object
#
# We use upstart compatible statuses in @state field
#
# • waiting : initial state.
# • starting : job is about to start.
# • pre-start : running pre-start section.
# • spawned : about to run script or exec section.
# • post-start : running post-start section.
# • running : interim state set after  post-start  section processed denoting job is running (But it may have no associated PID!)
# • pre-stop : running pre-stop section.
# • stopping : interim state set after pre-stop section processed.
# • killed : job is about to be stopped.
# • post-stop : running post-stop section

exports.Service = class Service extends queue.Queue

    init: ->
        super()
        @state = 'waiting'
        # Service goal (start or stop)
        @goal = undefined
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
        # Route event from dependent service
        sugar.relate( "depends", @id, depId, cb)

    # Remove dependence
    removeDependence: (depId, cb)->
        sugar.unrelate( "depends", @id, depId, cb)


    # Configure service and attach to groups
    configure: (params..., cb)->
        exports.log.info "Configure service #{@id}:", params

        config = (name)=>
            if name of params[0]
                @[name] = params[0][name]
            if not @[name]
                throw new Error("Service param #{name} not set")

        if params[0]
            try
                config "account"
                config "address"
                config "user"
                config "port"
            catch err
                return cb(err)
 
        # Init home 
        @home = "/home/#{@user}/.cloudpub"

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
    start: (params...,cb)->
        exports.log.info "Start service #{@id}"
        if @state not in ['waiting','stopping']
            return cb(null)
        @goal = "start"
        @state = "pre-start"
        # On start handler
        @configure params..., (err) =>
            return cb(err) if err
            @emit 'starting', @, cb

    # Stop service
    stop: (params...,cb)->
        exports.log.info "Stop service #{@id}"
        if @state not in ['running']
            return cb(null)
        @goal = "stop"
        @state = "stopping"
        # On start handler
        @configure params..., (err) =>
            return cb(err) if err
            @emit 'stopping', @, cb


    # Default 'starting' event handler
    starting: (event, cb)->
        exports.log.info "Starting service #{@id}"

        # Start service
        # Called @install and @startup internally
        async.waterfall [
                # Check dependencies
                (cb) =>
                    @groupState( @depends, cb )
                # If dependecies not ready, break waterfall
                (state, cb)=>
                    if state != 'up'
                        exports.log.warn "Wait for service dependencies", state, @depends
                        cb("BREAK")
                    else
                        cb(null)
                # Clear queue
                (cb) =>
                    queue.Queue.prototype.stop.call( @, cb )
                # Fill queue by install commands 
                (cb) =>
                    @install(cb)
                # Fill queue by startup commands
                (cb) =>
                    @startup(cb)
                # Subscribe to success event
                (cb) =>
                    @on 'success', 'started', @id
                    @save(cb)
                # Start queue
                (cb) =>
                    queue.Queue.prototype.start.call( @, cb )
            ], (err)->
                # Handle break
                if err == "BREAK" then return cb(null)
                cb(err)

    started: (event, cb)->
        exports.log.info "Service started: #{@id}"
        @setState "running", cb


    # Stop service
    stopping: (params..., cb)->
        exports.log.info "Stop service #{@id}"
        
        stop  = queue.Queue.prototype.stop
        start = queue.Queue.prototype.start
        
        if @state in ['down','maintain','error']
            return cb(null)
        
        @mode = 'stop'

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
            (cb) => start.call(@, params..., cb)
        ], cb

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

Service.relations = ['depends','children']

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
