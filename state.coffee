nconf   = require 'nconf'
_       = require 'underscore'
async   = require 'async'
events  = require 'events'
io      = require './io'
uuid    = require './uuid'

log = console

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
        log.debug "Save: #{@package}.#{@entity} [#{@id}] (#{@state}) #{@message}"
        #console.trace()
        # Save persistend fields
        @_children = undefined
        CACHE[ @id ] = @
        nconf.set("object:" + @id, @)
        nconf.set(@entity + ":" + @id, @id)
        nconf.save (err) =>
            cb and cb(err)

    # Clear and remove from storage
    clear: (cb) ->
        if @id
            delete CACHE[@id]
            log.info "Delete object #{@id}"
            nconf.clear('object:' + @id)
            nconf.clear( @entity + ":" + @id )
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
    
        write = log.info
        if @state == 'down'
            write = log.warn
        if @state == 'error'
            write = log.error
        write.call log, "State: #{@package}.#{@entity} [#{@id}] (#{@state}) #{@message}"
        @save (err)=>
            return cb and cb(err) if err
            @emit 'state', @, cb

    # Emit event to registered handlers
    emit: (name, event, cb)->
        entity = @entity
        # Helper load to call event listener
        call_handler = (handler, cb) ->
            # Load object from store
            load handler.id, (err, item)->
                return cb and cb(err) if err
                log.info "#{entity} emit #{name} to #{handler.id}::#{handler.handler}"
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
                    async.forEach @events[name], call_handler, cb
                else
                    cb(null)
        # Stupid coffee parser required this here
        ], (err) -> cb(err)

    # Register event handler
    # name = name of event
    # handler = name of method(event, cb)
    # id = object id to call handler
    on: (name, handler, id)->
        @events[name] ?=[]
        @events[name].push {handler, id}

    # Remove event handler
    mute: (name, handler, id)->
        if name of @events
            @events[name] = _.filter( @events[name], (h)->( not ((h.id == id) and (h.handler == handler)) ) )

exports.cache = CACHE = {}

# Create enity instance
exports.create = create = (id, entity, package, cb) ->
    if typeof(package) == 'function'
        cb = package
        package = entity
    if typeof(entity) == 'function'
        cb = entity
        package = entity = null
    blueprint = {}
    if _.isObject(id)
        blueprint = id
        id = blueprint.id
        entity = blueprint.entity or entity
        package = blueprint.package or package or entity
    if not (package and entity)
        return cb and cb( new Error("Entity type or package not set") )
    if not id
        id = uuid.v1()
    log.debug "Create #{package}.#{entity} [#{id}]"
    if not (package and entity)
        return cb and cb( new Error("Can't create null entity") )

    if id of CACHE
        return cb and cb( null, CACHE[id] )

    module = require('./' + package)

    entityClass = entity.charAt(0).toUpperCase() + entity.substring(1)
    Entity = module[ entityClass ]
    if not Entity
        cb and cb( new Error("Entity #{entity} not found in #{package}") )
    else
        obj = new Entity(id)
        obj.entity = entity
        obj.package = package
        _.extend obj, blueprint
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

    if id and not stored
        return cb and cb( new Error("Reference not found: [#{id}]") )
 
    create id, entity, package, (err, obj)->
        return cb and cb(err) if err
        if stored
            _.extend obj, stored
            log.debug "Loaded #{package}.#{entity} [#{id}]"
            if obj.loaded
                return obj.loaded cb
        cb and cb( null, obj )

exports.loadOrCreate = loadOrCreate = (id, entity, package, cb )->
    if typeof(package) == 'function'
        cb = package
        package = entity
    if typeof(entity) == 'function'
        cb = entity
        package = entity = null
    load id, entity, package, (err, obj)->
        return cb and cb(null, obj) if not err
        create id, entity, package, cb

# Query states by params and cb( error, [entities] )
exports.query = query = (entity, params, cb) ->
    if typeof(params) == 'function'
        cb = params
        params = []
    json = nconf.get(entity)
    if not json or (_.isArray(json) and json.length == 0)
        json =  {}

    load_resolve = (id, cb)->
        load id, (err, item)->
            return cb and cb(err) if err
            if item.resolve
                return item.resolve (err)->
                    cb and cb(err, item)
            else
                return cb and cb(null, item)

    # Load async each entity by key
    async.map _.keys(json), load_resolve, cb


exports.init = (app, cb)->

    nconf.argv()

    nconf.defaults {
        listen:3000
        test:false
    }

    if not nconf.get('test')
        nconf.file
            file: __dirname + '/snapshot.json'
    else
        nconf.file
            file: __dirname + '/test-snapshot.json'

    log = io.log
    cb and cb(null)