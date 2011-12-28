_       = require 'underscore'
async   = require 'async'
state   = require './state'
io      = require './io'
group   = require './group'
log     = console

#
# Work queue
#
exports.Queue = class Queue extends group.Group

    # Start executing of workers in queue
    start: (cb) ->
        log.info "Start queue #{@id}", @children
        if @children.length
            @startWorker @children[0], cb
        else
            @emit 'success', @, cb

    # Start worker with specific ID
    startWorker: (id, cb)->
        state.load id, (err, worker)=>
            return cb and cb(err) if err or worker.state == 'up'
            async.waterfall [
                (cb) => @setState(worker.state, worker.message, cb)
                (cb) => worker.setState( 'up', cb )
                (cb) => worker.start( cb )
            ], cb

    # Stop and delete worker
    stopWorker: (id, cb)->
        async.waterfall [
                (cb) -> state.load( id, cb )
                (worker, cb) -> worker.stop( cb )
                (cb) => @remove(id, cb)
            ], cb

    # Stop and delete all workers
    stop: (cb)->
        log.info "Stop queue #{@id}"
        # Clear all workers
        async.forEach @children,((id,cb)=>@stopWorker(id,cb)), cb

    # Worker error handler
    workerFailure: (worker, cb) ->
        log.error "Queue: Worker #{worker.id} failed"
        worker.setState 'error', (err)=>
            return cb and cb(err) if err
            @setState 'error', worker.message, cb

    # Worker success handler
    workerSuccess: (worker, cb) ->
        log.info "Queue: Worker #{worker.id} succeeded"
        @stopWorker worker.id, (err)=>
            return cb and cb(err) if err
            if _.isObject(worker.success)
                @setState worker.success.state, worker.success.message, (err)=>
                    return cb and cb(err) if err
                    process.nextTick => @start ((err) -> if err then exports.log.error "Start queue error: ", err)
                    cb and cb(null)
            else
                process.nextTick => @start ((err) -> if err then exports.log.error "Start queue error: ", err)
                cb and cb(null)

    # Create new worker
    submit: ( params, cb ) ->
        log.info "Queue: Submit " + JSON.stringify(params)
        state.create params, (err, worker) =>
            return cb and cb(err) if err

            worker.on 'failure', 'workerFailure', @id
            worker.on 'success', 'workerSuccess', @id

            async.series [
                (cb) => worker.save(cb)
                (cb) => @add(worker.id, cb)
            ], cb

exports.init = (app, cb)->
    app.register 'queue'
    log = io.log
    cb and cb( null )
