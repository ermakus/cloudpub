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
    # UP = all children is up
    # DOWN or ERROR = has down or error children
    # MAINTAIN = has up and maintain children
    updateState: (cb)->

        states   = {up:0,maintain:0,down:0,error:0}
        messages = {up:[],maintain:[],down:[],error:[]}

        checkState = (id, cb)->
            state.load id, (err, child)->
                # Ignore non-exist children
                return cb and cb(null) if err
                states[ child.state ] += 1
                messages[ child.state ].push child.message
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
            
            message = messages[st][0]

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

    deepClear: (cb)->
        async.series [
            (cb) => @each('clear', cb)
            (cb) => @clear(cb)
        ], cb
