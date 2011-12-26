_       = require 'underscore'
async   = require 'async'
state   = require './state'

log = console

# Object group
exports.Group = class Group extends state.State

    # Init instance
    init: ->
        super()
        # Children object IDs
        @children = []


    # Add children to list
    add: (id, cb) ->
        @children.push id
        @save cb

    # Remove children from list
    remove: (id, cb) ->
        if id in @children
            log.info "Remove #{id} from #{@children}"
            @children = _.without @children, id
            @save cb
        else
            cb and cb(null)

    # Run command for each children
    each: (method, cb)->

        process = (id, cb) ->
            state.load id, (err, instance) ->
                return cb and cb(err) if err
                log.info "Call method: #{method} of #{instance.id}"
                instance[method] (err)->
                    cb and cb( err, instance )

        async.forEach @children, process, cb

    # Update group state from children states
    # UP = all children is up
    # DOWN or ERROR = has down or error children
    # MAINTAIN = has up and maintain children
    updateState: (cb)->

        st = 'up'
        message = null

        checkState = (id, cb)->
            state.load id, (err, child)->
                # Ignore non-exist children
                return cb and cb(null) if err
                if (child.state == 'down') or (child.state == 'error')
                    st      = child.state
                    message = child.message
                    return cb and cb(null)
                if st == 'up' and child.state == 'maintain'
                    st   = child.state
                    message = child.message
                    return cb and cb(null)
                if st == 'up' and child.state == 'up'
                    st   = child.state
                    message = child.message
                return cb and cb(null)

        async.forEach @children, checkState, (err)=>
            return cb and cb(err) if err
            @setState st, message, cb

    # Resolve children IDs to objects from storage
    resolve: (cb)->
        async.map @children, state.load, (err, items)=>
            return cb and cb(err) if err
            @_children = items
            cb and cb(null)

    # Start children
    start: (cb)->
        async.series [
            (cb) => @each('start', cb)
            (cb) => @updateState(cb)
        ], cb

    # Stop children
    stop: (cb)->
        async.series [
            (cb) => @each('stop', cb)
            (cb) => @updateState(cb)
        ], cb

init = (app, cb)->
    log = exports.log
    cb and cb(null)
