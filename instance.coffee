async        = require 'async'
_            = require 'underscore'
account      = require './account'
serviceGroup = require './serviceGroup'
state        = require './state'
settings     = require './settings'
sugar        = require './sugar'

#
# Instance is remote host to execute services
#
exports.Instance = class Instance extends serviceGroup.ServiceGroup

    init: ->
        super()
        # Server address
        @address = undefined
        # SSH user
        @user = undefined
        # Owner account
        @account = undefined
        # Port to listen
        @port = "8080"

    
    # Launch instance
    # Will start some core services
    launch: (event, cb) ->
        exports.log.info "Start instance", @id

        if event
            # Merge some params
            @account = event.account or @account
            @address = event.address or @address
            @user    = event.user    or @user
            @port    = event.port    or @port

        if not (@address and @user)
            return cb( new Error('Invalid address or user') )

        # Declare services
        services = [
            { id:"runtime",  entity:'runtime' }
            { id:"proxy",    entity:'proxy',    domain:@address, default:true, port:@port, depends:['runtime'] }
            { id:"cloudpub", entity:'cloudpub', domain:@address, address:@address, port:(@port+1), depends:['runtime','proxy'] }
        ]

        async.waterfall [
                # Create services
                (cb)=>
                    @create(services, cb)
                # Link instance with account
                (cb)=>
                    sugar.relate 'children', @account, @id, cb
                # Route events to account
                (cb)=>
                    sugar.route 'state', @id, 'serviceState', @account, cb
                # Start services
                (cb)=>
                    @start(event, cb)
            ], (err)->cb(err)

    clear: (cb)->
        sugar.unrelate 'children', @account, @id, state.defaultCallback
        super(null)


# List instancies for account
listInstances = (entity, params, cb)->
    # Load account and instancies
    state.load params.account, (err, account)->
        # Load each instance
        async.map account.children, state.loadWithChildren, cb

# Init HTTP request handlers
exports.init = (app, cb)->
    return cb(null) if not app
    # Create or load instance
    item = (params, entity, cb) ->
        if params.cloud == 'ec2'
            entity = "ec2"
        state.load params.id, entity, cb

    # Register CRUD handler
    app.register 'instance', listInstances, item

    # Create localhost instance
    state.loadOrCreate settings.ID, 'instance', (err, instance)->
        return cb(err) if err
        instance.user = settings.USER
        instance.address = settings.DOMAIN
        instance.port = settings.PORT
        instance.save cb
