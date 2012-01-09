nconf    = require 'nconf'
_        = require 'underscore'
async    = require 'async'
events   = require 'events'
io       = require './io'
settings = require './settings'

# Module ref
state = exports

# List of storage backends
BACKENDS = [
    require './rest'
    require './memory'
]

# Methods backend supported
BACKEND_METHODS = [ 'create', 'load', 'save', 'clear', 'loadOrCreate', 'query', 'loadWithChildren' ]

#
# Persistent state
#
exports.State = class State

    # Create or load state
    # @entity = entity name
    # @id = entity ID (if not null then state retreived from storage)
    constructor: (@id)->
        @init()

    # Init state defaults
    init: ->
        @events = {}
        @state = 'down'
        # Each object has machine instance ID
        @instance = settings.ID

    # Return type of object
    type: ->
        results = (/function (.{1,})\(/).exec((this).constructor.toString())
        if results?.length then results[1] else "Unknown"

    # Save state
    save: (cb) ->
        return cb and cb(null) unless @id
        exports.log.debug "Save: #{@package}.#{@entity} [#{@id}] (#{@state}) #{@message}"
        # Remove resolved children before save
        @_children = undefined
        # Add timestump for cache maintaining
        @stump = Date.now()
        exports.save @, cb

    # Clear and remove from storage
    clear: (cb) ->
        if @id
            exports.clear @, (err) =>
                @id = undefined
                cb and cb( null )
        else
            cb and cb( null )

    # Emit event to registered handlers
    emit: (name, event, cb=state.defaultCallback)->
        # Helper to call event listener
        callHandler = (handler, cb) =>
            # Clone event from original
            cloneEvent = _.clone(event)
            cloneEvent.source = @id
            cloneEvent.target = handler.id
            cloneEvent.method = handler.handler
            # Marshall event over system rourer
            exports.log.error "Emit #{name} from \##{@id} as #{handler.handler} to \##{handler.id}"
            state.emit name, cloneEvent, cb

        callLocal = (cb)=>
            if typeof(@[name]) == 'function'
                exports.log.warn "Call local handler"
                @[name](event, cb)
            else
                cb(null)

        callLocal (err)=>
            if name of @events
                async.forEach @events[name], callHandler, cb
            else
                cb(null)

    # Handle event, called internally by router
    eventTarget: (name, event, cb)->
        if not event?.method
            return cb( new Error("Target event.method not set: " + event?.type() ) )
        if typeof( @[event.method] ) == 'function'
            @[event.method](event, cb)
        else
            return cb( new Error("Target method not found: " + @type() + "." + event.method) )


    # Register event handler
    # name = name of event
    # handler = name of method(event, cb)
    # id = object id to call handler
    on: (name, handler, id)->
        @mute name, handler, id
        @events[name] ?=[]
        @events[name].push {handler, id}

    # Remove event handler
    mute: (name, handler, id)->
        if name of @events
            @events[name] = _.filter( @events[name], (h)->( not ((h.id == id) and (h.handler == handler)) ) )

    # Update state and message
    # also emit 'state' event
    setState: (state, message, cb) ->
        if state
            @state = state
        if typeof(message) == 'function'
            cb = message
        else
            @message = message
    
        write = exports.log.info
        if @state == 'down'
            write = exports.log.warn
        if @state == 'error'
            write = exports.log.error
        write.call exports.log, "State: #{@package}.#{@entity} [#{@id}] (#{@state}) #{@message}"
        @save (err)=>
            return cb and cb(err) if err
            @emit 'state', @, cb


# Emit event to event.target
# Name is event namespace
# If target object is not local, route it over socket.io
state.emit = (name, event, cb=state.defautCallback)->
    if not event?.target
        cb(new Error("Event target not set"))
    # Load target object
    state.load event.target, (err, obj)->
        return cb(err) if err
        # if object instance is local (i.e. equals ID)
        if not obj.instance or (obj.instance == settings.ID)
            exports.log.debug "Route event to", event.target
            # then handle event locally
            obj.eventTarget name, event, cb
        else
            exports.log.debug "Route remote", event.target, obj.instance
            # else route event over socket.io
            io.emit name, event, cb

# Call method from backend stack
backendHandler = (method)->

    return (args..., callback)->
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

# Init proxy storage methods
for method in BACKEND_METHODS
    exports[method] = backendHandler method

