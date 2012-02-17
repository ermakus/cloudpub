_       = require 'underscore'
async   = require 'async'
sugar   = require './sugar'
state   = require './state'
io      = require './io'
group   = require './group'

#
# Queue of services
#
# This is group of services that executed one by one
#
exports.Queue = class Queue extends group.Group

    # Start executing of services in queue
    startup: ( me, cb ) ->
        sugar.vargs arguments
        exports.log.info "Queue: Start", @id
        @emit 'started', @, (err)=>
            return cb(err) if err
            @continue(cb)

    # Start executing of services in queue
    continue: (params..., cb) ->
        sugar.vargs arguments
        process.nextTick =>
            if @children.length
                exports.log.debug "Queue: Continue", @children[0]
                @startService @children[0], params..., state.defaultCallback
            else
                exports.log.info "Queue: Empty"
                @shutdown( @, state.defaultCallback )
        cb(null)

    # Start service with specific ID
    startService: (id, params..., cb)->
        sugar.vargs arguments
        exports.log.debug "Queue: Start service", id
        state.load id, (err, service)=>
            return cb(err)  if (err)
            async.series [
                    (cb) => @setState(service.state, service.message, cb)
                    (cb) => service.start( params..., cb )
                ], (err)->cb(err)

    # Stop and delete service
    stopService: (id, params..., cb)->
        sugar.vargs arguments
        exports.log.debug "Queue: Stop service", id, params
        async.series [
                (cb) => @remove(id, cb)
                (cb) => sugar.emit('clear', id,  cb)
            ], (err)->cb(err)

    # Queue has been override group state management
    serviceState: (name, params..., cb) ->
        sugar.vargs arguments
        if name == 'success'
            return @serviceSuccess(params..., cb)
        if name == 'failure'
            return @serviceFailure(params..., cb)
        cb(null)

    # Service error handler
    serviceFailure: (service, cb) ->
        sugar.vargs arguments
        exports.log.error "Queue: Service failed", service.id
        async.series [
            (cb) => service.setState( 'error', cb )
            (cb) => @setState( 'error', service.message, cb )
            (cb) => @emit( 'failure', @, cb )
        ], cb

    # Service success handler
    serviceSuccess: (service, cb) ->
        sugar.vargs arguments
        exports.log.debug "Queue: Service succeeded", service.id
        async.series [
            # Activate success trigger (TODO: pass to submit)
            (cb)=>
                if _.isObject(service.success)
                    @setState service.success.state, service.success.message, cb
                else
                    cb(null)
            # Stop service
            (cb)=>
                @stopService(service.id, service, cb)
            (cb)=>
                @continue(cb)
            ], (err)-> cb(err)
