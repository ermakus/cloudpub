_       = require 'underscore'
async   = require 'async'
state   = require './state'
io      = require './io'

log     = console

#
# Work queue
#
exports.Queue = class Queue extends state.State

    init: ->
        super()
        # List of worker IDs
        @workers = []

    resolve: (cb)->
        async.map @workers, state.load, (err, items)=>
            return cb and cb(err) if err
            @workers = items
            cb and cb(null)

    start: (cb) ->
        if @workers.length
            state.load @workers[0], (err, worker) =>
                return cb and cb(err) if err
                return cb and cb(err) if (worker.state == 'up')
                log.info "Starting worker #{worker.id}", worker.id
                worker.start (err)=>
                    return cb and cb(err) if err
                    @setState 'maintain', 'Work in progress', cb
        else
            return cb and cb(null)

    stopWorker: (id, cb)->
        state.load id, (err, worker) =>
            return cb and cb(err) if err
            worker.clear (err) =>
                return cb and cb(err) if err
                @workers =  _.without @workers, id
                @save cb

    stop: (cb)->
        # Clear all workers
        async.forEach @workers,((id,cb)=>@stopWorker(id,cb)), cb

    # Worker error handler
    failure: (event, cb) ->
        @setState 'error', event.error.message, cb

    # Worker success handler
    success: (event, cb) ->
        log.info "Queue: Worker #{event.worker.id} succeeded"
        @stopWorker event.worker.id, (err)=>
            return cb and cb(err) if err
            if _.isObject(event.worker.success)
                @setState event.worker.success.state, event.worker.success.message, (err)=>
                    return cb and cb(err) if err
                    @start cb
            @start cb

    # Create new worker
    submit: ( params, cb ) ->
        log.info "Queue: Submit ", params
        state.create null, params.task, params.package or 'worker', (err, worker) =>
            return cb and cb(err) if err
            worker.state = 'maintain'
            _.extend worker, params

            worker.on 'failure', 'failure', @id
            worker.on 'success', 'success', @id

            worker.save (err) =>
                return cb and cb( err ) if err
                @workers.push worker.id
                @save (err) =>
                    return cb and cb( err ) if err
                    @start cb

exports.init = (app, cb)->
    app.register 'queue'
    log = io.log
    cb and cb( null )
