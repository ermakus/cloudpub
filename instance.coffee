async        = require 'async'
_            = require 'underscore'
account      = require './account'
serviceGroup = require './serviceGroup'
state        = require './state'
settings     = require './settings'

# Instance class
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

    start: (params..., cb) ->
        exports.log.info "Start instance", @id
        # Instance is equal to ID for this class
        @instance = @id

        if params[0]
            # Merge some params (TODO)
            @account = params[0].account or @account
            @address = params[0].address or @address
            @user    = params[0].user    or @user
            @port    = params[0].port    or @port

        if not (@address and @user)
            return cb and cb( new Error('Invalid address or user') )

        # Declare services
        @children = [
            { id:"cloudpub", entity:'cloudpub', domain:@address, address:@address, port:(@port+1), depends:['runtime','proxy'] }
            { id:"runtime",  entity:'runtime' }
            { id:"proxy",    entity:'proxy',    domain:@address, default:true, port:@port, depends:['runtime'] }
        ]
        super(params..., cb)

# List instancies for account
listInstances = (entity, params, cb)->
    # Load account and services
    state.loadWithChildren params.account, (err, account)->
        # Collect unique apps from services
        apps = _.uniq( service.instance for service in account._children)
        apps = _.compact apps
        # Load each and return
        async.map apps, state.loadWithChildren, cb

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
