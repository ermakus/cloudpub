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
        # Instance ID service run on
        @instance = undefined
        # Application ID to run
        @app = undefined
        # User account to run
        @user = undefined
        # Domain
        @domain = 'cloudpub.us'

    # Run service on instance
    runService: (instanceId, serviceType, params, cb)->
        log.info "Run service #{serviceType} on #{instanceId}"
        state.create null, serviceType, (err, service) =>
            return cb and cb(err) if err
            # Subscribe to state event
            service.on 'state', 'serviceState', @id
            async.series [
                (cb)=> service.setApp(@id,cb),
                (cb)=> service.setInstance(instanceId,cb),
                (cb)=> service.install(cb),
                (cb)=> service.startup(cb),
            ], cb

    # Run service on instance
    stopService: (serviceId, params, cb)->

        state.load serviceId, (err, service) =>
            return cb and cb(err) if err
            if service.instance not in params.instance
                return cb and cb(null)

            ifDelete = (cb)->
                if params.data == 'delete'
                    service.uninstall(cb)
                else
                    cb and cb(null)

            async.series [
                (cb) => service.shutdown(cb),
                (cb) => ifUninstall(cb),
            ], cb

    # Service state event handler
    serviceState: (event, cb)->
        # Replicate last service state
        @setState event.state, event.message, cb
    
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

    state.create 'app-cloudpub', 'app', (err, item) ->
        return cb and cb(err) if err
        app.id = 'cloudpub'
        app.title = 'Cloudpub Node'
        item.save cb
