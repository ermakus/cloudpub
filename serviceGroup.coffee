_       = require 'underscore'
async   = require 'async'

group    = require './group'
state    = require './state'

#
# Service group
# 
exports.ServiceGroup = class ServiceGroup extends group.Group

    # Run service by ID or JSON
    startService: (serviceId, cb)->
        exports.log.info "Start service #{serviceId}"
        state.load serviceId, (err, service) =>
            return cb and cb(err) if err
            # Subscribe to state event
            async.series [
                (cb) => service.save(cb)
                (cb) => service.stop(cb)
                (cb) => service.install(cb)
                (cb) => service.startup(cb)
                (cb) => service.start(cb)
            ], (err)-> cb( null, service.id )

    # Stop service by ID
    stopService: (serviceId, doUninstall, cb)->
        exports.log.info "Stop service #{serviceId}"
        state.load serviceId, (err, service) =>
            return cb and cb(err) if err

            ifUninstall = (cb)->
                if doUninstall
                    service.uninstall(cb)
                else
                    cb and cb(null)

            async.series [
                (cb) => service.stop(cb)
                (cb) => service.shutdown(cb)
                (cb) => ifUninstall(cb)
                (cb) => service.start(cb)
            ], cb

    # Configure single service
    configureService: (serviceId, params, cb)->
        async.waterfall [
            (cb) -> state.loadOrCreate(serviceId, cb)
            (service, cbb) ->
                service.configure params, (err) ->
                    cbb(err, service)
            (service, cb) => @add(service.id, cb)
        ], cb

    # Configure service group
    # Accepted params:
    # services = array of service IDs or JSONs. If ommited then @children is used
    # address  = remote server address
    # user     = service POSIX account
    # account  = Account ID of service
    # app      = App ID of service
    # instance = Instance ID of service
    configure: (params, cb) ->
        exports.log.info "Configure service group #{@id}"
        if not params.services
            return cb and cb(new Error("Services list not passed"))
        async.series [
            (cb)=> @save(cb)
            (cb)=> async.forEach params.services, ((serviceId, cb)=>@configureService( serviceId, params, cb )), cb
            (cb)=> @save(cb)
        ], cb

    # Create, configure and start services
    # See configure for accepted params
    startup: (params, cb) ->
        exports.log.info "Startup service group #{@id}"
        @mute 'success', 'suicide', @id
        @mute 'failure', 'suicide', @id
        async.series [
            (cb) => @configure params, cb
            (cb) => async.forEach @children, ((serviceId, cb)=>@startService( serviceId, cb )), cb
            (cb) => @save(cb)
        ], cb

    # Stop service group
    # Accepted params:
    # data = (keep|delete) Keep or delete data and group itself after shutdown
    shutdown: (params, cb) ->
        exports.log.info "Shutdown service group #{@id}"
        doUninstall = params.data == 'delete'
        async.series [
            # Subscribe to suicide handler
            (cb)=>
                if doUninstall
                    @on 'failure', 'suicide', @id
                    @on 'success', 'suicide', @id
                    @save cb
                else
                    cb(null)
            # Stop all services
            (cb)=>
                if @children.length
                    async.forEach @children, ((serviceId, cb)=>@stopService( serviceId, doUninstall, cb )), cb
                else
                    @emit 'success', @, cb
        ], cb

    # Service state event handler
    serviceState: (event, cb)->
        # Replicate last service state
        @updateState cb
 
    # Service state handler called when uninstall. 
    # Commits suicide after work complete
    suicide: (app, cb)->
        exports.log.info "Suicide service group: #{@id}"
        # Delete object on next tick
        process.nextTick =>
            async.series [
                (cb) => @each 'clear', cb
                (cb) => @setState 'down', 'Deleted', cb
                (cb) => @clear(cb)
            ], cb
        cb(null)
