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

    startup: (params, cb) ->
        @account = params.account
        @address = params.address
        @user    = params.user
        if not (@address and @user)
            return cb and cb( new Error('Invalid address or user') )
        if not params.id
            @id = 'i-' + @address.split('.').join('-')
        params.services = [
            { entity:'cloudpub', package:'cloudpub' }
        ]
        super(params, cb)

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
