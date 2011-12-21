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


    add: (id, cb) ->
        @children.push id
        @save cb

    remove: (id, cb) ->
        if id in @children
            @children = _.except @children, id
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

    resolve: (cb)->
        async.map @children, state.load, (err, items)=>
            return cb and cb(err) if err
            @children = items
            cb and cb(null)

    # Start service
    start: (cb)->
        @each 'start', cb

    # Stop service
    stop: (cb)->
        @each 'stop', cb

