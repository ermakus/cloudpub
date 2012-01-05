nconf   = require 'nconf'
_       = require 'underscore'
async   = require 'async'
events  = require 'events'
io      = require './io'
uuid    = require './uuid'

# List of storage backends
BACKENDS = [
    require './memory'
]

backendHandler = (method)->
    return (args...)->
        callback = _.find args, _.isFunction
        res = [null]
        callBackend = (backend, cb)->
            # Change original callback 
            myargs = _.without args, callback
            myargs.push ->
                res = arguments
                cb( arguments[0] )
            # Call backend
            backend[method].apply backend, myargs

        async.forEachSeries BACKENDS, callBackend, (err)->
            callback.apply @, res


# Init storage methods
for method in [ 'create', 'load', 'save', 'clear', 'loadOrCreate' ]
    exports[method] = backendHandler method

#
# Persistent state
#
exports.State = class State

    # Last state name ('up','maintain','down','error')
    state  : 'down'

    # Last message
    message: 'innocent'

    # Create or load state
    # @entity = entity name
    # @id = entity ID (if not null then state retreived from storage)
    constructor: (@id)->
        @init()

    # Init state defaults
    init: ->
        @events = {}
        @state = 'down'
        @message = 'innocent'

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

    # Logging: update state name and last message
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

    # Emit event to registered handlers
    emit: (name, event, cb)->
        entity = @entity
        # Helper load to call event listener
        callHandler = (handler, cb) ->
            # Load object from store
            exports.load handler.id, (err, item)->
                return cb and cb(err) if err
                exports.log.info "#{entity} emit #{name} to #{handler.id}::#{handler.handler}"
                # Call handler by name
                item[handler.handler] event, cb

        async.series [
            # Call this.name function if defined
            (cb) =>
                if typeof( @[name] ) == 'function'
                    @[name](event, cb)
                else
                    cb(null)
            # Load listeners and dispatch event to
            (cb) =>
                if name of @events
                    async.forEach @events[name], callHandler, cb
                else
                    cb(null)
        # Stupid coffee parser required this here
        ], (err) -> cb(err)

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



