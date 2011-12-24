_       = require 'underscore'
async   = require 'async'
state   = require './state'

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
            @children = _.without @children, id
            @save cb
        else
            cb and cb(null)

    # Run command for each children
    each: (method, cb)->

        process = (id, cb) ->
            state.load id, (err, instance) ->
                return cb and cb(err) if err
                console.log "Call method: #{method} of", instance
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
                return cb and cb(err) if err
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
            @children = items
            cb and cb(null)

    # Start children
    start: (cb)->
        @each 'start', cb

    # Stop children
    stop: (cb)->
        @each 'stop', cb

