async        = require 'async'
_            = require 'underscore'
account      = require './account'
serviceGroup = require './serviceGroup'
state        = require './state'

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

    configure: (params, cb) ->
        @account = params.account
        @address = params.address
        @user    = params.user
        if not (@address and @user)
            return cb and cb( new Error('Invalid address or user') )
        params.instance = @id
        params.services = [
            { id:'runtime-' + @id, entity:'runtime', package:'runtime', domain:@address, default:true, port:"8088" }
        ]
        super(params, cb)

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

    # Create or load instance
    item = (params, entity, cb) ->
        if params.cloud == 'ec2'
            entity = "ec2"
        state.load params.id, entity, cb

    # Register CRUD handler
    app.register 'instance', listInstances, item

    cb and cb( null )
