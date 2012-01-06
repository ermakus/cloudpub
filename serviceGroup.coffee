_       = require 'underscore'
async   = require 'async'
queue   = require './queue'
state   = require './state'

#
# Service group
# 
exports.ServiceGroup = class ServiceGroup extends queue.Queue

    # Run service by ID or JSON
    startService: (serviceId, cb)->
        exports.log.info "Start service #{serviceId}"
        state.load serviceId, (err, service) =>
            return cb and cb(err) if err
            # Exit if already up
            if service.state in ['up','maintain']
                return cb(null)

                # Start service
                async.series [
                        (cb) => service.stop(cb)
                        (cb) =>
                            if not service.isInstalled
                                service.install(cb)
                            else
                                cb(null)
                        (cb) =>
                            if not service.isInstalled
                                service.isInstalled = true
                                service.save(cb)
                        (cb) =>
                            service.startup(cb)
                        (cb) => service.start(cb)
                    ], (err)-> cb( null, service.id )

    # Stop service by ID
    stopService: (serviceId, doUninstall, cb)->
        exports.log.info "Stop service #{serviceId}"
        state.load serviceId, (err, service) =>
            return cb and cb(err) if err
            if service.state in ['down','maintain','error']
                return cb(null)

            ifUninstall = (cb)->
                if doUninstall and service.isInstalled
                    service.uninstall (err)->
                        return cb(err) if err
                        service.isInstalled = false
                        service.save(cb)
                else
                    cb(null)

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
            (cb)=> @reorder(cb)
            (cb)=> @save(cb)
        ], cb

    # Create, configure and start services
    # See configure for accepted params
    startup: (params, cb) ->
        exports.log.info "Startup service group #{@id}"
        @mode = "startup"
        @mute 'success', 'suicide', @id
        @mute 'failure', 'suicide', @id
        async.series [
            (cb) => @save cb
            (cb) => @configure params, cb
            (cb) => async.forEach @children, ((serviceId, cb)=>@startService( serviceId, cb )), cb
            (cb) => @save(cb)
            (cb) => @start(cb)
        ], cb

    # Stop service group
    # Accepted params:
    # data = (keep|delete) Keep or delete data and group itself after shutdown
    shutdown: (params, cb) ->
        exports.log.info "Shutdown service group #{@id}"
        doUninstall = params.data == 'delete'
        @mode = "shutdown"
        async.series [
            (cb)=> @save cb
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
            (cb) => @start(cb)
        ], cb

    # Service state event handler
    serviceState: (event, cb)->
        # Update group state from services
        @message = event.message
        @updateState (err)=>
            return cb(err) if err
            # If group starting up or shutting down, repeat this
            if @mode == 'startup' and @state != 'up'
                return process.nextTick =>
                    async.forEach @children, ((serviceId, cb)=>@startService( serviceId, cb )), cb
            if @mode == 'shutdown' and @state != 'down'
                return process.nextTick =>
                    async.forEach @children, ((serviceId, cb)=>@stopService( serviceId, cb )), cb
            cb(null)
 
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
