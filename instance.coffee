async   = require 'async'
_       = require 'underscore'
account = require './account'
command = require './command'
group   = require './group'
state   = require './state'
app     = require './app'

# Instance class
exports.Instance = class Instance extends group.Group

    init: ->
        super()
        # Server address
        @address = undefined
        # SSH user
        @user = undefined
        # Owner account
        @account = undefined
        
    # Service state event handler
    serviceState: (event, cb)->
        # Replicate last service state
        @updateState cb
 
    configureService: (serviceId, params, cb)->
        exports.log.info "Configure service: #{serviceId}", params
        state.load serviceId, (err, service)->
            return cb and cb(err) if err
            service.user = params.user
            service.address = params.address
            service.home = "/home/#{params.user}/.cloudpub"
            service.save cb

    configure: (params, cb) ->
        @account = params.account
        @address = params.address
        @user = params.user
        if not (@address and @user)
            return cb and cb( new Error('Invalid address or user') )
        if not params.id
            @id = 'i-' + @address.split('.').join('-')
        async.series [
            (cb)=> async.forEach @children, ((serviceId, cb)=>@configureService( serviceId, params, cb )), cb
            (cb)=> @save(cb)
        ], cb

    # Start instance
    startup: (params, ccb) ->
        async.series [
                (cb)=> @configure(params, cb),
                (cb)=> @install(cb),
        ], ccb

    # Stop instance
    shutdown: (params, cb) ->
        if params.mode == 'shutdown'
            @uninstall cb
        else
            async.series [
                (cb)=>@setState('maintain','On maintaince', cb)
                (cb)=>@stop(cb)
            ], cb

    install: (cb) ->
        state.load 'app-cloudpub', (err, app)=>
            return cb and cb(err) if err
            app.mute 'state', 'uninstallState', @id
            app.startup {instance:@id, account:@account}, cb

    uninstall: (cb) ->
        state.load 'app-cloudpub', (err, app)=>
            return cb and cb(err) if err
            app.on 'state', 'uninstallState', @id
            app.shutdown {instance:@id, account:@account, data:'delete'}, cb

    uninstallState: (app, cb)->
        if app.state != 'down' or app.message != 'Service uninstalled' then return cb(null)
        process.nextTick =>
            async.series [
                (cb) => @setState 'down', 'Server deleted', cb
                (cb) => @each 'clear', cb
                (cb) => @clear(cb)
            ], cb
        cb(null)

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
