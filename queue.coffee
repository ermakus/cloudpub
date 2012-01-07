_       = require 'underscore'
async   = require 'async'
state   = require './state'
io      = require './io'
group   = require './group'

#
# Work queue
#
exports.Queue = class Queue extends group.Group

    # Start executing of workers in queue
    start: (params...,cb) ->
        if @children.length
            exports.log.debug "Queue: Start", @children[0]
            @startWorker @children[0], params, cb
        else
            exports.log.info "Queue: Empty"
            @emit 'success', @, cb

    # Stop and delete all workers
    stop: (params...,cb)->
        exports.log.info "Stop queue #{@id}"
        # Clear all workers
        async.forEach @children,((id,cb)=>@stopWorker(id,params...,cb)), cb

    # Submit task
    submit: ( params, cb ) ->
        # If array passed then submit all
        if params and _.isArray(params)
            return @submitAll params, cb

        exports.log.info "Queue: Submit " + JSON.stringify(params)
        state.create params, (err, worker) =>
            return cb and cb(err) if err

            # Inherit defaults from queue 
            worker.user    = @user    or worker.user
            worker.address = @address or worker.address
            worker.home    = @home    or worker.home

            worker.on 'failure', 'workerFailure', @id
            worker.on 'success', 'workerSuccess', @id

            async.series [
                (cb) => worker.save(cb)
                (cb) => @add(worker.id, cb)
                (cb) => @save(cb)
            ], cb

    # Submit job list
    submitAll: ( list, cb ) ->
        async.forEachSeries list, ((item, cb)=>@submit(item, cb)), cb

    # Internals
   
    # Start worker with specific ID
    startWorker: (id, params, cb)->
        state.load id, (err, worker)=>
            return cb(err) if (err)
            return cb(null) if worker.state == 'up'
            async.waterfall [
                    (cb) => @setState(worker.state, worker.message, cb)
                    (cb) => worker.setState( 'up', cb )
                    (cb) => worker.start( params..., cb )
                ], cb

    # Stop and delete worker
    stopWorker: (id, params, cb)->
        async.waterfall [
                (cb) -> state.load( id, cb )
                (worker, cb) -> worker.stop( params..., cb )
                (cb) => @remove(id, cb)
            ], cb


    # Worker error handler
    workerFailure: (worker, cb) ->
        exports.log.error "Queue: Worker failed", worker.id
        async.series [
            (cb) => worker.setState( 'error', cb )
            (cb) => @setState( 'error', worker.message, cb )
            (cb) => @emit( 'failure', @, cb )
        ], cb

    # Worker success handler
    workerSuccess: (worker, cb) ->
        exports.log.info "Queue: Worker succeeded", worker.id
        async.series [
            # Activate success worker trigger (TODO: pass to submit)
            (cb)=>
                if _.isObject(worker.success)
                    @setState worker.success.state, worker.success.message, cb
                else
                    cb(null)
            # Stop worker
            (cb)=>
                @stopWorker(worker.id, [], cb)
            # Start queue again
            (cb)=>
                # On the next tick
                process.nextTick =>
                    exports.log.info "Queue: Continue", @children
                    @start (err) ->
                        if err then exports.log.error "Queue: Continue error", err.message
                cb(null)
            ], cb



exports.init = (app, cb)->
    if app then app.register 'queue'
    cb and cb( null )
