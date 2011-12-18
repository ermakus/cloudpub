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
    constructor: (@id)->
        @init()

    # Init state defaults
    init: ->
        @state = 'down'
        @message = 'innocent'

    # Save state
    save: (cb) ->
        return cb and cb(null) unless @id
        console.log "Save: #{@package}.#{@entity} [#{@id}] (#{@state}) #{@message}"
        #console.trace()
        # Save persistend fields
        nconf.set("object:" + @id, @)
        nconf.set(@entity + ":" + @id, @id)
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
        console.log "State: #{@package}.#{@entity} [#{@id}] (#{@state}) #{@message}"
        io.emit 'anton', { entity:@entity, state:@state, message:@message }
        @emit 'state', @state, @message
        @save cb


# Create enity instance
exports.create = create = (id, entity, package, cb) ->
    if typeof(package) == 'function'
        cb = package
        package = entity
    if typeof(entity) == 'function'
        return cb and cb( new Error("Can't create null entity") )
    console.log "Create #{package}.#{entity} [#{id}]"
    module = require('./' + package)
    entityClass = entity.charAt(0).toUpperCase() + entity.substring(1).toLowerCase()
    Entity = module[ entityClass ]
    if not Entity
        cb and cb( new Error("Entity #{entity} not found in #{package}") )
    else
        obj = new Entity(id)
        obj.entity = entity
        obj.package = package
        cb and cb( null, obj )

# Load state from module
exports.load = load = (id, entity, package, cb) ->
    if typeof(package) == 'function'
        cb = package
        package = entity
    if typeof(entity) == 'function'
        cb = entity
        package = entity = null

    stored = null
    if id
        stored = nconf.get("object:" + id)
    if stored
        if stored.entity
            package = entity = stored.entity
        if stored.package
            package = stored.package

    create id, entity, package, (err, obj)->
        return cb and cb(err) if err
        if stored then _.extend obj, stored
        console.log "Loaded #{package}.#{entity} [#{id}]"
        cb and cb( null, obj )

# Query states by params and cb( error, [entities] )
exports.query = query = (entity, params, cb) ->
    if typeof(params) == 'function'
        cb = params
        params = []
    console.log "Query #{entity}", params
    json = nconf.get(entity)
    if not json or (_.isArray(json) and json.length == 0)
        json =  {}
    # Load async each entity by key
    async.map _.keys(json), load, cb

