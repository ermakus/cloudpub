# 
# Default object factory and cache
#
nconf = require 'nconf'
uuid = require './uuid'
async = require 'async'
_ = require 'underscore'

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
    exports.log.debug "Create #{package}.#{entity} [#{id}]"
    if not (package and entity)
        return cb and cb( new Error("Can't create null entity") )

    if id of CACHE
        return cb and cb( null, CACHE[id] )

    try
        module = require('./' + package)
    catch e
        exports.log.warn "Try global package", package
        module = require(package)

    # Attach logger to loaded module
    if typeof( module.log ) == 'undefined'
        module.log = exports.log

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

# Clear entity from cache
exports.clear =(entity, cb)->
        # Clear local cache
        delete CACHE[entity.id]
        exports.log.info "Delete object #{entity.id}"
        # Remove from backend
        nconf.clear('object:' + entity.id)
        nconf.clear('index:' + entity.entity + ":" + entity.id )
        nconf.save (err) =>
            cb and cb(err)

# Save entity to storage
exports.save = (entity, cb)->
        # Save to cache and backend
        CACHE[ entity.id ] = entity
        nconf.set("object:" + entity.id, entity)
        nconf.set("index:" + entity.entity + ":" + entity.id, entity.message)
        nconf.save (err) =>
            cb and cb(err)

# Load state from module
exports.load = load = (id, entity, package, cb) ->

    if typeof(package) == 'function'
        cb = package
        package = entity
    if typeof(entity) == 'function'
        cb = entity
        package = entity = null
    
    stored = null
    
    if _.isObject(id)
        stored = id
        id = stored.id

    if id
        stored = nconf.get("object:" + id)

    if stored
        if stored.entity
            package = entity = stored.entity
        if stored.package
            package = stored.package

    if id and not stored
        #return cb( null, { id:id, state:'error', message:'Ghost reference' } )
        return cb( new Error("Reference not found: [#{id}]") )
 
    create id, entity, package, (err, obj)->
        return cb and cb(err) if err
        if stored
            _.extend obj, stored
            exports.log.debug "Loaded #{package}.#{entity} [#{id}]"
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
        create id, entity, package, (err, obj)->
            obj.save (err)->
                cb(err, obj)

exports.loadWithChildren = loadWithChildren = (id, cb)->
    load id, (err, item)->
        return cb and cb(err) if err
        if item.resolve
            return item.resolve (err)->
                cb and cb(err, item)
        else
            return cb and cb(null, item)


# Query states by params and cb( error, [entities] )
exports.query = query = (entity, params, cb) ->

    if typeof(params) == 'function'
        cb = params
        params = []


    # Get all indexes
    if(entity=='*')
        indexes = nconf.get('index')
        async.map _.keys(indexes), query, (err, entities)->
            results = _.reduce entities, (memo, list)-> memo.concat list
            return cb( err, results )

    # Load items from index
    json = nconf.get('index:' + entity)
    if not json or (_.isArray(json) and json.length == 0)
        json =  {}


    # Load async each entity by key
    async.map _.keys(json), loadWithChildren, cb

