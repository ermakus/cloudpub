_       = require 'underscore'
async   = require 'async'
state   = require './state'
io      = require './io'
group   = require './group'
tsort   = require './topologicalSort.js'

#
# Work queue
#
exports.Queue = class Queue extends group.Group

    # Reorder with dependency topological sort
    reorder: (cb)->
        async.map @children, state.load, (err, services)=>
            reordered = []
            for index in tsort.topologicalSort( services )
                reordered.unshift @children[index]
            exports.log.info "New order", reordered
            @children = reordered
            cb(null)

    # Start executing of workers in queue
    start: (cb) ->
        exports.log.info "Start queue #{@id}", @children
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
        exports.log.info "Stop queue #{@id}"
        # Clear all workers
        async.forEach @children,((id,cb)=>@stopWorker(id,cb)), cb

    # Worker error handler
    workerFailure: (worker, cb) ->
        exports.log.error "Queue: Worker #{worker.source} failed"
        async.series [
            (cb) => worker.setState( 'error', cb )
            (cb) => @setState( 'error', worker.message, cb )
            (cb) => @emit( 'failure', @, cb )
        ], cb

    # Worker success handler
    workerSuccess: (worker, cb) ->
        exports.log.info "Queue: Worker #{worker.id} succeeded"
        @stopWorker worker.id, (err)=>
            return cb and cb(err) if err
            if _.isObject(worker.success)
                @setState worker.success.state, worker.success.message, (err)=>
                    return cb and cb(err) if err
                    process.nextTick => @start ((err) -> if err then exports.log.error "Start queue error: ", err.message)
                    cb and cb(null)
            else
                process.nextTick => @start ((err) -> if err then exports.log.error "Start queue error: ", err.message)
                cb and cb(null)

    # Submit job list
    submitAll: ( list, cb ) ->
        async.forEachSeries list, ((item, cb)=>@submit(item, cb)), cb

    # Submit job
    submit: ( params, cb ) ->
        # If array passed then submit all
        if params and _.isArray(params)
            return @submitAll params, cb

        exports.log.info "Queue: Submit " + JSON.stringify(params)
        state.create params, (err, worker) =>
            return cb and cb(err) if err

            # Worker inherit queue params
            _.defaults worker, @

            worker.on 'failure', 'workerFailure', @id
            worker.on 'success', 'workerSuccess', @id

            async.series [
                (cb) => worker.save(cb)
                (cb) => @add(worker.id, cb)
                (cb) => @reorder(cb)
                (cb) => @save(cb)
            ], cb

exports.init = (app, cb)->
    if app then app.register 'queue'
    cb and cb( null )
