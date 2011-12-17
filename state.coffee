nconf   = require 'nconf'
_       = require 'underscore'
async   = require 'async'
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
        console.log "Save: #{@entity}:#{@id} [#{@state}] #{@message}"
        return cb and cb(null) unless @id
        # Save persistend fields
        nconf.set(@entity + ":" + @id, @)
        nconf.save (err) =>
            cb and cb(err)

    # Clear and remove from storage
    clear: (cb) ->
        if @id
            nconf.clear(@entity + ':' + @id)
            @id = undefined
            nconf.save (err) =>
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
        
        console.log "State: #{@entity}.#{@id}: [#{@state}] #{@message}"
        io.emit 'anton', { entity:@entity, state:@state, message:@message }
        @emit 'state', @state, @message
        @save cb

# Load state from module
exports.pload = pload = (package, entity, id, cb) ->
    module = require('./' + package)
    entityClass = entity.charAt(0).toUpperCase() + entity.substring(1).toLowerCase()
    console.log "Loading #{entityClass} id=#{id}"
    Entity = module[ entityClass ]
    if not Entity
        cb and cb( new Error("Entity #{entityClass} not found in #{package}") )
    else
        obj = new Entity( entity, id )
        cb and cb( null, obj )

# Load default module state
exports.load = load = (entity, id, cb) -> exports.pload entity, entity, id, cb

# Query states by params and cb( error, [entities] )
exports.query = (entity, params, cb) ->
    if typeof(params) == 'function'
        cb = params
        params = []
    console.log "Query #{entity}", params
    json = nconf.get(entity)
    if not json or (_.isArray(json) and json.length == 0)
        json =  {}
    # Load async each entity by key
    async.map _.keys(json), ((k,c)->load entity, k, c), cb


