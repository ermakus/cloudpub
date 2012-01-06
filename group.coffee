_       = require 'underscore'
async   = require 'async'
state   = require './state'

exports.log = console

# Object group
exports.Group = class Group extends state.State

    # Init instance
    init: ->
        super()
        # Children object IDs
        @children = []


    # Add children to list
    add: (id, cb) ->
        if id in @children then return cb and cb(null)
        exports.log.info "Add #{id} to #{@id}"
        @children.push id
        @save cb

    # Remove children from list
    remove: (id, cb) ->
        if id in @children
            exports.log.info "Remove #{id} from #{@id}"
            @children = _.without @children, id
            @save cb
        else
            cb and cb(null)

    # Run command for each children
    each: (method, cb)->

        process = (id, cb) ->
            state.load id, (err, instance) ->
                return cb and cb(err) if err
                exports.log.info "Call method: #{method} of #{instance.id}"
                instance[method] (err)->
                    cb and cb( err, instance )

        async.forEachSeries @children, process, cb

    # Update group state from children states
    # up       = all children is up
    # down     = all children is down
    # error    = at least 1 child error
    # maintain = any other
    updateState: (cb)->
        exports.log.info "Update group #{@id} state"

        states   = {up:0,maintain:0,down:0,error:0}
        workers  = 0

        checkState = (id, cb)->
            state.load id, (err, child)->
                # Ignore non-exist children
                return cb and cb(null) if err
                states[ child.state ] += 1
                cb and cb(null)

        async.forEach @children, checkState, (err)=>
            return cb and cb(err) if err
            st = 'maintain'
            if states['up'] == @children.length
                st = 'up'
            if states['down'] == @children.length
                st = 'down'
            if states['error'] > 0
                st = 'error'
            
            async.series [
                (cb)=>
                    if st == 'up'
                        exports.log.info "Group #{@id} success"
                        @emit('success', @, cb)
                    else
                        cb(null)
                (cb)=>
                    if st == 'error'
                        exports.log.info "Group #{@id} failure"
                        @emit('failure', @, cb)
                    else
                        cb(null)
                (cb)=>
                    @setState(st, @message, cb)
            ], cb

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

    deepClear: (cb)->
        async.series [
            (cb) => @each('clear', cb)
            (cb) => @clear(cb)
        ], cb
