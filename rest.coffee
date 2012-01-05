# 
# REST object factory and WEB service
#
http = require 'http'
settings = require './settings'
state = require './state'

if settings.MASTER
    master = http.createClient(settings.MASTER_PORT, settings.MASTER)
else
    master = undefined

NO_MASTER = new Error("Master not set")

# Clear entity from cache
exports.clear =(entity, cb)->
    cb and cb( new Error("Not implemented") )

# Save entity to storage
exports.save = (entity, cb)->
    cb and cb( new Error("Not implemented") )

# Load state from module
exports.load = load = (id, entity, package, cb) ->
    if typeof(package) == 'function'
        cb = package
        package = entity
    if typeof(entity) == 'function'
        cb = entity
        package = entity = null
    
    return cb( NO_MASTER ) if not master

    master.get options, (err, res)->
        return cb(err) if err
        cb null, JSON.parse res.body

# Query states by params and cb( error, [entities] )
exports.query = query = (entity, params, cb) ->
    if typeof(params) == 'function'
        cb = params
        params = []
    cb and cb( new Error("Not implemented") )

# Init web service
exports.init = (app, cb)->
    return cb(null) if not app

    # REST GET handler
    app.get "/api/all/:id", (req, resp)->
        state.load req.params.id, (err, obj)->
            if err
                resp.send err, 500
            else
                resp.send obj


    cb(null)

