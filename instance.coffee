async   = require 'async'
_       = require 'underscore'
account = require './account'
command = require './command'
group   = require './group'
state   = require './state'

# Instance class
exports.Instance = class Instance extends group.Group

    init: ->
        super()

    # Service state event handler
    serviceState: (event, cb)->
        # Replicate last service state
        @updateState cb
 
    configureService: (serviceId, params, cb)->
        state.load serviceId, (err, service)->
            return cb and cb(err) if err
            service.user = params.user
            service.address = params.address
            service.save cb

    configure: (params, cb) ->
        @address = params.address
        @user = params.user
        if not (@address and @user)
            return cb and cb( new Error('Invalid address or user') )
        if not params.id
            @id = 'i-' + @address.split('.').join('-')
        async.forEach @children, ((serviceId, cb)=>@configureService( serviceId, params, cb )), cb

    # Start instance
    startup: (params, ccb) ->
        async.series [
                (cb)=> @stop(cb),
                (cb)=> @configure(params, cb),
                (cb)=> @install(cb),
                (cb)=> @start(cb),
        ], ccb

    # Stop instance
    shutdown: (params, cb) ->
        ifUninstall = (cb)=>
            if params.mode == 'shutdown'
                @uninstall cb
            else
                cb(null)
    
        async.series [
            (cb)=> @stop(cb),
            (cb)=> ifUninstall(cb),
            (cb)=> @setState('maintain','On maintaince', cb),
            (cb)=> @start(cb),
        ], cb

    install: (cb) ->
        cb and cb(null)

    uninstall: (cb) ->
        cb and cb(null)

# Init HTTP request handlers
exports.init = (app, cb)->

    # List of instances
    list = (entity, cb)->

        async.parallel [
            async.apply( state.query, 'instance' ),
            async.apply( state.query, 'ec2' )
        ], (err, result)->
            return cb and cb(err) if err
            items = []
            for item in result
                items = items.concat item
            cb and cb(null, items)

    # Create or load instance
    item = (params, entity, cb) ->
        if params.cloud == 'ec2'
            entity = "ec2"
        state.load params.id, entity, cb

    # Register CRUD handler
    app.register 'instance', list, item

    cb and cb( null )
