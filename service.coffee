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
        @depends = []
        # Depends to, updated automatically
        @dependsTo = []

    # Add and resolve single dependence
    addDependence: (depId, cb)->
        exports.log.debug "Add dependency", depId, "to", @id
        async.waterfall [
            # Update from
            (cb)=>
                @depends ||= []
                if depId not in @depends
                    @depends.push depId
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
                    dependent.on 'state', 'dependentState', @id
                    dependent.save(cb)
                else
                    cb(null)
            ], cb

    # Remove dependence
    removeDependence: (depId, cb)->
        exports.log.debug "Remove dependency", depId, "from", @id
        async.waterfall [
            # Update from
            (cb)=>
                if depId in @depends
                    @depends = _.without @depends, depId
                    @save(cb)
                else
                    cb(null)
            # Load target object
            (cb)=>
                state.load(depId, cb)
            # Update to
            (dependent, cb)=>
                if @id in dependent.dependentTo
                    dependent.dependsTo = _.without dependent.dependsTo, @id
                    dependent.mute 'state', 'dependentState', @id
                    dependent.save(cb)
                else
                    cb(null)
            ], cb

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
            # Attach to listeners (FIXME)
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
                    async.forEach( @depends or [], ((id, cb)=>@removeDependence(id, cb)), cb)
                # Call super
                (cb)=>
                    queue.Queue.prototype.clear.call @, cb
            ], cb


    dependentState: (event,cb)->
        if @mode == 'start'
            exports.log.info "Try to start service again", event.id, event.state
            process.nextTick => @start(state.defaultCallback)
        cb(null)

    # Start service by ID or JSON
    start: (params..., cb)->
        exports.log.info "Start service #{@id}"

        # Exit if already up
        if @state in ['up', 'maintain']
            exports.log.warn "Service already started", @id
            return queue.Queue.prototype.start.call( @, params..., cb )

        # Start service
        # Called @install and @startup internally
        async.waterfall [
                # Stop service first
                (cb) =>
                    @stop(cb)
                # Configure service
                (cb) =>
                    @mode = 'start'
                    @configure(params..., cb)
                # Check dependencies
                (cb) =>
                    @groupState( @depends, cb )
                # If dependecies not ready, break waterfall
                (state, cb)=>
                    if state != 'up'
                        exports.log.warn "Wait service dependencies", state, @depends
                        cb("BREAK")
                    else
                        cb(null)
                # Call install handler if not installed
                (cb) =>
                    if not @isInstalled
                        @install(cb)
                    else
                        cb(null)
                # Mark as installed
                (cb) =>
                    if not @isInstalled
                        @isInstalled = true
                        @save(cb)
                    else
                        cb(null)
                # Call startup handler
                (cb) =>
                    @startup(cb)
                # Start queue
                (cb) =>
                    queue.Queue.prototype.start.call( @, params..., cb )
            ], (err)->
                # Handle break
                if err == "BREAK" then return cb(null)
                cb(err)

    # Stop service
    stop: (params..., cb)->
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
