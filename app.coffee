fs      = require 'fs'
_       = require 'underscore'
async   = require 'async'

io    = require './io'
group = require './group'
state = require './state'

log = console

# Default service object


exports.App = class App extends group.Group

    init: ->
        super()
        @name = "Master Node"
        # Instance ID service run on
        @instance = undefined
        # Application ID to run
        @app = undefined
        # User account to run
        @user = undefined
        # Domain
        @domain = 'cloudpub.us'


    # Load or create service
    service: (id, instanceId, serviceType, cb)->
        state.load id, (err, service)=>
            return cb and cb(null, service) if service
            state.create id, serviceType, (err, service)=>
                service.on 'state', 'serviceState', @id
                async.series [
                    (cb)=> service.setApp(@id,cb),
                    (cb)=> service.setInstance(instanceId,cb),
                ], (err) -> cb and cb( err, service )

    # Run service on instance
    runService: (instanceId, serviceType, params, cb)->
        log.info "Run service #{serviceType} on #{instanceId}"
        serviceId = @id + '-' + instanceId
        @service serviceId, instanceId, serviceType, (err, service) =>
            return cb and cb(err) if err
            # Subscribe to state event
            async.series [
                (cb)=> service.stop(cb),
                (cb)=> service.install(cb),
                (cb)=> service.startup(cb),
            ], cb

    # Stop service on instance
    stopService: (serviceId, params, cb)->
        log.info "Stop service #{serviceId}"
        state.load serviceId, (err, service) =>
            return cb and cb(err) if err

            ifUninstall = (cb)->
                if params.data == 'delete'
                    service.uninstall(cb)
                else
                    cb and cb(null)

            async.series [
                (cb) => service.stop(cb),
                (cb) => service.shutdown(cb),
                (cb) => ifUninstall(cb)
            ], cb

    # Service state event handler
    serviceState: (event, cb)->
        # Replicate last service state
        @updateState cb
    
    # Start service
    startup: (params, cb)->
        if typeof(params) == 'function'
            cb = params
            params = {}
        params ||= {}
        params.instance ||= []
        if _.isString(params.instance)
            params.instance = [params.instance]

        serviceType = 'cloudpub'
        async.forEach params.instance, ((instanceId, cb) => @runService(instanceId, serviceType, params, cb)), cb

    # Stop service
    shutdown: (params, cb)->
        if typeof(params) == 'function'
            cb = params
            params = {}
        params ?= {}
        params.instance ?= []
        async.forEach @children, ((serviceId, cb) => @stopService(serviceId, params, cb)), cb

# Init request handlers here
exports.init = (app, cb)->

    log = io.log

    app.register 'app'

    state.load 'app-cloudpub', (err)->
        if not err then return cb and cb(null)
        state.create 'app-cloudpub', 'app', (err, item) ->
            return cb and cb(err) if err
            app.id = 'cloudpub'
            app.title = 'Cloudpub Node'
            item.save cb
