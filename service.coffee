fs       = require 'fs'
_        = require 'underscore'
async    = require 'async'
assert   = require 'assert'
settings = require './settings'
command  = require './command'
state    = require './state'
sugar    = require './sugar'

#### Service class
#
# Base class for all services.
#
##### Service life cycle events:
#
# - starting
# - install (*)
# - installed (*)
# - startup
# - started
#
# - shutdown
# - stopped
# - uninstall (*)
# - uninstalled (*)
# - success or failure
#
# (*) - is optional events

exports.Service = class Service extends state.State

    init: ->
        super()
        # State, one of **up**, **down**, **maintain**
        @state = 'down'
        # Service goal (**start**, **stop** or undefined)
        @goal = undefined
        # Default state message
        @message = 'Waiting...'
        # Service owner account ID
        @account = undefined
        # Address of SSH server to run
        @address = settings.HOST
        # Posix user to run
        @user = settings.USER
        # Service public domain
        @domain = settings.DOMAIN
        # Service public port
        @port = settings.PORT
        # Interface to bind
        @interface = "127.0.0.1"

    #### Add and resolve single dependence
    addDependence: (depId, cb)->
        sugar.vargs( arguments )
        sugar.relate( "depends", @id, depId, cb)

    #### Remove dependence
    removeDependence: (depId, cb)->
        sugar.vargs( arguments )
        # Ignore non-existend references
        sugar.unrelate( "depends", @id, depId, ((err)->cb(null)))


    #### Configure service and attach to groups
    configure: (params..., cb)->
        sugar.vargs( arguments )
        exports.log.info "Configure service",  @id, params
        
        # Configure service
        async.series [
            # Save config
            (cb)=> @save(cb)
            # Resolve dependencies
            (cb)=> async.forEach(@depends or [], ((id, cb)=>@addDependence(id,cb)), cb)
        ], (err)->cb(err)

    #### Start service
    # - *params* passed to `configure`
    start: (params...,cb)->
        sugar.vargs( arguments )
        exports.log.info "Service start", @id
        # Check depndenies
        sugar.groupState @depends or [], (err, st)=>
            return cb(err) if err
            # If all is up then starting
            if st == null or st == 'up' or st == 'error'
                @goal = "start"
                @state = "maintain"
                # Configure service first
                @configure params..., (err) =>
                    return cb(err) if err
                    @emit 'starting', @, cb
            # else do nothing
            else
                cb(null)


    #### Delete service and detach it from dependcies
    clear: (cb)->
        sugar.vargs( arguments )
        exports.log.info "Service delete", @id
        async.series [
                # Detach from dependencies
                (cb)=>
                    async.forEach( @depends or [], ((id, cb)=>@removeDependence(id, cb)), cb)
                # Call super
                (cb)=>
                    state.State.prototype.clear.call( @, cb )
            ], (err)->cb(err)

    #### Update state and message
    # also emit 'state' event
    # Can be called with service object as first parameter
    # (useful for state event handling)
    setState: (state, message, cb) ->
        sugar.vargs(arguments)
        if _.isFunction(message)
            cb = message
            message = null

        if state and _.isObject(state)
            message = state.message
            state = state.state
        else
            
            message = message or @message
            state   = state or @state

        # Do not fire same event twice
        fire = (message != @message) or (state != @state)
        @state = state
        @message = message
        
        exports.log.info "State: \##{@id} [#{@state}] #{@message}"

        if not fire
            return cb(null)

        @save (err)=>
            return cb(err) if err
            @emit 'state', @, cb


    #### Starting event handler
    starting: (service, cb)->
        sugar.vargs( arguments )
        exports.log.info "Service starting", @id
        if not @isInstalled
            @emit('install', @, cb)
        else
            @emit('startup', @, cb)

    #### Install event handler
    install: (service, cb) ->
        sugar.vargs( arguments )
        exports.log.debug "Service install", @id
        @emit 'installed', @, cb

    #### Installed event handler
    installed: (service, cb)->
        sugar.vargs( arguments )
        exports.log.debug "Service installed", @id
        @isInstalled = true
        @save (err)=>
            return cb(err) if err
            @emit('startup', @, cb)

    #### Startup handler
    startup: (service, cb) ->
        sugar.vargs( arguments )
        exports.log.debug "Service startup", @id
        @emit 'started', @, cb

    #### Started event handler
    started: (service, cb)->
        sugar.vargs( arguments )
        exports.log.info "Service started", @id
        @state = 'up'
        @goal  = undefined
        @save cb

    #### Stop service
    # - *params* is passed to `configure`
    stop: (params...,cb)->
        sugar.vargs( arguments )
        exports.log.info "Service stop", @id
        # Check depndenies
        sugar.groupState @_depends or [], (err, st)=>
            return cb(err) if err
            # If all is down then stopping
            if true #st == null or st == 'down'
                @goal = "stop"
                @state = "maintain"
                @configure params..., (err) =>
                    return cb(err) if err
                    @emit 'shutdown', @, cb
            else
                # else do nothing
                cb(null)

    #### Shutdown event handler
    shutdown: (service, cb) ->
        sugar.vargs( arguments )
        exports.log.info "Service shutdown", @id
        @emit 'stopped', @, cb

    #### Stopping event handler
    stopped: (service, cb)->
        sugar.vargs( arguments )
        exports.log.info "Service stopped", @id, @state
        @state = 'down'
        @goal  = undefined
        @save (err)=>
            return cb(err) if err
            if @doUninstall
                @emit 'uninstall', @, cb
            else
                @emit 'success', @, (err)=>
                    return cb(err) if err
                    if @commitSuicide
                        @clear(cb)
                    else
                        cb(null)

    #### Uninstall event handler
    uninstall: (service, cb) ->
        sugar.vargs( arguments )
        exports.log.info "Service uninstall", @id
        @installed = false
        @save (err)=>
            return cb(err) if err
            @emit 'uninstalled', @, cb

    #### Uninstalled event handler
    uninstalled: (service, cb)->
        sugar.vargs( arguments )
        exports.log.info "Service uninstalled", @id
        @emit 'success', @, (err)=>
            return cb(err) if err
            if @commitSuicide
                @clear(cb)
            else
                @save(cb)


# Get list of all services for account
listServices = (entity, params, cb)->

    async.waterfall [
        # Load account
        (cb) ->
            state.load params.account, cb
        # Load services
        (account, cb)->
            async.map account.children, state.loadWithChildren, cb
        # Merge services in one collection
        (services, cb)->
            cb(null, _.reduce( services, ((memo, item)->memo.concat(item._children)), [] ))
    ], cb

getService = (params, entity, cb)->
    state.loadOrCreate params.id, 'module', (err, module)->
        cb(err, module)

# Init request handlers here
exports.init = (app, cb)->
    return cb(null) if not app
    # List of services
    app.register 'service', listServices, getService
    cb and cb(null)
