#
# Default object factory and cache
#
uuid = require './uuid'
async = require 'async'
_ = require 'underscore'
fs = require 'fs'

# The only global variable for the app
# Has refs to all objects indexed by id
exports.CACHE = CACHE = {}

filename = (id) -> __dirname + "/data/" + encodeURI(id)

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
    if not (package and entity)
        return cb and cb( new Error("Can't create null entity") )

    exports.log.debug "Create #{package}.#{entity} [#{id}]"

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
        # Delete object
        delete exports.CACHE[entity.id]
        fs.unlink( filename(entity.id), cb)

# Save entity to storage
exports.save = (entity, cb)->
        # Save to cache and backend
        exports.CACHE[ entity.id ] = entity
        fs.writeFile( filename(entity.id), JSON.stringify( entity ), cb)

# Resolve object from the filesystem
exports.resolve = resolve = (id, cb)->
    # Try to open file
    fs.readFile filename(id), (err, json)->
        if err
            err = new Error("Reference not found: #{id}")
            err.notFound = true
            return cb( err )
        else
            exports.log.debug "Loaded", id
            return cb( null, JSON.parse(json) )

# Load state from module
exports.load = load = (id, entity, package, cb) ->

    if typeof(package) == 'function'
        cb = package
        package = entity
    if typeof(entity) == 'function'
        cb = entity
        package = entity = null

    blueprint = null

    if _.isObject(id)
        blueprint = id
        id = blueprint.id

    # Check if in cache
    if id of exports.CACHE
        return cb( null, exports.CACHE[id] )

    # Resolve object from memory or storage
    resolve id, (err, stored)->
        return cb(err) if err
        exports.log.debug "Loaded #{stored.package}.#{stored.entity} #{id}"
        # Apply defaults to just loaded object
        if blueprint
            _.defaults stored, blueprint
        # Take type from object if not set
        entity = entity or stored.entity
        package = package or stored.package
        create( stored, entity, package, cb )

# Load or create object
exports.loadOrCreate = loadOrCreate = (id, entity, package, cb )->
    if typeof(package) == 'function'
        cb = package
        package = entity
    if typeof(entity) == 'function'
        cb = entity
        package = entity = null
    load id, entity, package, (err, obj)->
        return cb(err, obj) if not err
        return cb(err, obj) if not err.notFound
        create id, entity, package, (err, obj)->
            return cb(err) if err
            obj.save (err)->
                cb(err, obj)

# This method replace children IDs by objects itself
# Return clone of the object!
exports.loadWithChildren = loadWithChildren = (id, cb)->
    load id, (err, item)->
        return cb and cb(err) if err
        clone = _.clone( item )
        if clone.children
            async.map clone.children, load, (err, children)->
                return cb(err) if err
                clone.children = children
                cb and cb(err, clone)
        else
            cb(null, clone)

# Query states by params and cb( error, [entities] )
exports.query = query = (index, params..., cb) ->
    console.log "CACHE", exports.CACHE, @
    # If global index requested
    if(index=='*')
        # return complete cache
        cb( null, _.values(exports.CACHE) )
    else
        # else try to load named index
        load index, (err, index)->
            return cb(err) if err and not err.notFound
            # If index not found return empty array
            if err
                return cb( null, [] )
            # else load objects from index
            async.map(index.children, load, cb)
