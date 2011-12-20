async   = require 'async'
_       = require 'underscore'
account = require './account'
command = require './command'
state   = require './state'
queue   = require './queue'

# Instance class
exports.Instance = class Instance extends queue.Queue

    init: ->
        super()

    configure: (params, cb) ->

        @address = params.address
        @user = params.user

        if not (@address and @user)
            return cb and cb( new Error('Invalid address or user' + params.cloud) )
        
        if not params.id
            @id = 'i-' + @address.split('.').join('-')
        
        @setState 'maintain', "Configured with #{@user}@#{@address}", cb

    # Start instance
    start: (params, cb) ->
        if typeof(params) == 'function'
            cb = params
            params = {}
        # Super
        start = queue.Queue.prototype.start

        async.series [
                (cb)=> @configure(params, cb),
                (cb)=> @install(params, cb),
                (cb)=> start.call(@, cb),
        ], cb

    # Stop instance
    stop: (params, cb) ->
        if typeof(params) == 'function'
            cb = params
            params = {}

        ifUninstall = (cb)=>
            if params.mode == 'shutdown'
                @uninstall params, cb
            else
                cb(null)
    
        stop = queue.Queue.prototype.stop

        async.series [
            (cb) => @setState("maintain", "In maintaince mode", cb),
            (cb) => ifUninstall(cb),
            (cb) => stop.call(@,cb)
        ], cb

    submit: (task, params, cb) ->
        params.address = @address
        params.user = @user
        super task, params, cb

    install: (params, cb) ->
        state.load 'cloudpub', 'cloudpub', (err, service) =>
            service.instance = [@id]
            service.start cb

    uninstall: (params, cb) ->
        cb and cb(null)

# Init HTTP request handlers
exports.init = (app, cb)->

    # List of instances
    list = (entity, cb)->
        # Resolve workers for each instance
        resolve = (item, cb)->
            async.map item.workers, state.load, (err, workers)->
                item.workers = workers
                cb and cb(null, item)

        query = (entity, cb)->
            state.query entity, (err, items)->
                return cb and cb(err) if err
                async.forEach items, resolve, (err)->
                    cb and cb(err, items)
 
        async.parallel [
            async.apply( query, 'instance' ),
            async.apply( query, 'ec2' )
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
