fs      = require 'fs'
_       = require 'underscore'
async   = require 'async'
account = require './account'
group   = require './group'
state   = require './state'

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
    service: (id, accountId, instanceId, serviceType, cb)->
        state.load id, (err, service)=>
            return cb and cb(null, service) if not err
            state.create id, serviceType, (err, service)=>
                return cb and cb(err) if err
                async.series [
                    (cb)=> service.save(cb)
                    (cb)=> service.setApp(@id,cb)
                    (cb)=> service.setInstance(instanceId,cb)
                    (cb)=> service.setAccount(accountId,cb)
                    (cb)=> service.save(cb)
                ], (err) -> cb and cb( err, service )

    # Run service on instance
    runService: (accountId, instanceId, serviceType, params, cb)->
        log.info "Run service #{serviceType} on #{instanceId}"
        serviceId = @id + '-' + instanceId + '-' + accountId
        @service serviceId, accountId, instanceId, serviceType, (err, service) =>
            return cb and cb(err) if err
            # Subscribe to state event
            async.series [
                (cb) => service.stop(cb)
                (cb) => service.install(cb)
                (cb) => service.startup(cb)
                (cb) => service.start(cb)
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
                (cb) => service.stop(cb)
                (cb) => service.shutdown(cb)
                (cb) => ifUninstall(cb)
                (cb) => service.start(cb)
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
        async.forEach params.instance, ((instanceId, cb) => @runService(params.account, instanceId, serviceType, params, cb)), cb

    # Stop service
    shutdown: (params, cb)->
        if typeof(params) == 'function'
            cb = params
            params = {}
        params ?= {}
        params.instance ?= []
        
        async.forEach @children, ((serviceId, cb) => @stopService(serviceId, params, cb)), cb

create_app = (url, acc, cb)->
    state.loadOrCreate account.sha1( url ), 'app', (err, app)->
        return cb and cb(err) if err
        app.source = url
        app.account = acc
        app.save (err)->
            cb and cb(err, app)

# Init request handlers here
exports.init = (app, cb)->

    log = exports.log

    app.register 'app'

    app.post '/api/create/app', (req, resp)->
        url = req.param('url')
        if not url
            return resp.send 'URL is required', 500
        
        create_app url, req.session.uid, (err, app)->
            if err then return resp.send err, 500
            resp.send true

    state.load 'app-cloudpub', (err)->
        if not err then return cb and cb(null)
        state.create 'app-cloudpub', 'app', (err, item) ->
            return cb and cb(err) if err
            app.id = 'cloudpub'
            app.title = 'Cloudpub Node'
            item.save cb
