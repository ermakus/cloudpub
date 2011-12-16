nconf   = require 'nconf'
_       = require 'underscore'
events  = require 'events'
io      = require './io'

#
# Persistent state
#
exports.State = class State extends events.EventEmitter

    # Last state name ('up','maintain','down','error')
    state  : 'down'

    # Last message
    message: 'innocent'

    # Create or load state
    # @entity = entity name
    # @id = entity ID (if not null then state retreived from storage)
    constructor: (@entity, @id)->
        if @id
            # Load local porperties form persistent store
            _.extend @, nconf.get(@entity + ':' +@id)
        else
            # Unsaved

    # Save state
    save: (cb) ->
        return cb and cb(null) unless @id
        # Save persistend fields
        nconf.set(@entity + ":" + @id, @)
        nconf.save (err) =>
            if not err then @emit 'saved'
            cb and cb(err)

    # Clear and remove from storage
    clear: (cb) ->
        if @id
            nconf.clear(@entity + ':' + @id)
            @id = undefined
            nconf.save (err) =>
                if not err then @emit 'cleared'
                cb and cb(err)
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
        io.message 'anton', {state:@state, message:@message}
        @save (err) =>
            if err
                @state = 'error'
                @message = 'State save error: ' + err
            else
                @emit 'state', state, message
            console.log "#{@entity}.#{@id}: [#{@state}] #{@message}"
            cb and cb(err)

exports.list = (entity) ->
    nconf.get(entity)
