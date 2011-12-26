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

    start: (cb) ->
        log.info "Start queue #{@id}", @children
        if @children.length
            state.load @children[0], (err, worker) =>
                return cb and cb(err) if err
                return cb and cb(err) if (worker.state == 'up')
                log.info "Starting worker #{worker.id}", worker.id
                worker.setState 'up', (err)=>
                    return cb and cb(err) if err
                    worker.start (err)=>
                        return cb and cb(err) if err
                        @updateState cb
        else
            @emit 'success', @, cb

    stopWorker: (id, cb)->
        async.waterfall [
                (cb) -> state.load( id, cb )
                (worker, cb) -> worker.clear( cb )
                (cb) => @remove(id, cb)
            ], cb

    stop: (cb)->
        log.info "Stop queue #{@id}"
        # Clear all workers
        async.forEach @children,((id,cb)=>@stopWorker(id,cb)), cb

    # Worker error handler
    failure: (worker, cb) ->
        log.error "Queue: Worker #{worker.id} failed"
        @setState 'error', worker.message, cb

    # Worker success handler
    success: (worker, cb) ->
        if not cb
            cb = (err)->
                console.log "Queue success handler error", err
        log.info "Queue: Worker #{worker.id} succeeded"
        @stopWorker worker.id, (err)=>
            return cb and cb(err) if err
            if _.isObject(worker.success)
                @setState worker.success.state, worker.success.message, (err)=>
                    return cb and cb(err) if err
                    @start cb
            else
                @start cb

    # Create new worker
    submit: ( params, cb ) ->
        log.info "Queue: Submit " + JSON.stringify(params)
        state.create params, (err, worker) =>
            return cb and cb(err) if err
            worker.state = 'maintain'

            worker.on 'failure', 'failure', @id
            worker.on 'success', 'success', @id

            worker.save (err) =>
                @add worker.id, cb

exports.init = (app, cb)->
    app.register 'queue'
    log = io.log
    cb and cb( null )
