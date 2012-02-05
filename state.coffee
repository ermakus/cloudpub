#### This module contains persistent state management functions

nconf    = require 'nconf'
_        = require 'underscore'
async    = require 'async'
events   = require 'events'
uuid     = require './uuid'
io       = require './io'
settings = require './settings'
sugar    = require './sugar'

# Module ref
state = exports

# UUID generator
state.uuid = uuid.v1

# List of storage backends
BACKENDS = [
    require './rest'
    require './memory'
]

# Methods backend supported
BACKEND_METHODS = [ 'create', 'load', 'save', 'clear', 'loadOrCreate', 'query', 'loadWithChildren' ]

#### Persistent state
exports.State = class State

    #### Create or load state
    # - *id* is entity ID
    constructor: (@id)->
        @init()

    #### Init state defaults
    init: ->
        # Event handlers
        @events = {}
        # Each object has machine instance ID
        @instance = settings.ID

    #### Return type of object
    type: ->
        results = (/function (.{1,})\(/).exec((this).constructor.toString())
        if results?.length then results[1] else "Unknown"

    # Set object properties and save
    set: (props, cb)->
        sugar.vargs arguments
        _.extend( @, props )
        @save(cb)

    #### Save state
    save: (cb) ->
        sugar.vargs(arguments)
        return cb(null) unless @id
        exports.log.debug "Save: #{@package}.#{@entity} [#{@id}] (#{@state}) #{@message}"
        # Remove resolved children before save
        @_children = undefined
        # Add timestump for cache maintaining
        @stump = Date.now()
        exports.save @, cb

    #### Clear and remove from storage
    clear: (cb) ->
        sugar.vargs(arguments)
        if @id
            exports.log.debug "Delete state", @id
            exports.clear @, (err) =>
                @id = undefined
                cb( null )
        else
            cb( null )

    #### Handle event and dispatch to registered handlers
    # This method will call this[name] function if defined
    emit: (name, params..., cb)->
        sugar.vargs(arguments)
        async.series [
            # Fire event to catch all hook, if registered
            (cb)=>
                if '*' of @events
                    async.forEach(@events['*'], ((h, cb)->sugar.emit(h.handler, h.id, name, params..., cb)), cb)
                else
                    cb(null)
            # Call local hook
            (cb)=>
                if typeof(@[name]) == 'function'
                    exports.log.debug "Handle event #{name} by \##{@id}"
                    @[name](params..., cb)
                else
                    cb(null)
            # Route to subscribers
            (cb)=>
                if name of @events
                    async.forEach(@events[name], ((h, cb)->sugar.emit(h.handler, h.id, params..., cb)), cb)
                else
                    cb(null)
        ], (err)->cb(err)

    #### Register event handler
    # - name is name of event
    # - handler is name of method(event, cb)
    # - id is object id to call handler
    on: (name, handler, id)->
        @mute name, handler, id
        @events[name] ?=[]
        @events[name].push {handler, id}

    #### Remove event handler
    mute: (name, handler, id)->
        if name of @events
            @events[name] = _.filter( @events[name], (h)->( not ((h.id == id) and (h.handler == handler)) ) )

# Helper to call method from backend stack
backendHandler = (method)->

    return (args..., callback=state.defaultCallback)->
        sugar.vargs(arguments)

        callBackend = (memo, backend, cb)->

            # Avoid strange (async?) bug with null item
            if not backend
                return
            if (not backend) or (method not of backend)
                return cb(null, memo)
            # Call backend
            backend[method] args..., (err, result...)->
                cb( err, result )

        async.reduce BACKENDS, [], callBackend, (err, result)->
            callback( err, result... )

# Create backend methods
for method in BACKEND_METHODS
    exports[method] = backendHandler method

