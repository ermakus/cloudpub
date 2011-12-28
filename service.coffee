fs      = require 'fs'
_       = require 'underscore'
async   = require 'async'

account  = require './account'
queue    = require './queue'
command  = require './command'
state    = require './state'

# Default service object


exports.Service = class Service extends queue.Queue

    init: ->
        super()
        # Owner account
        @account = undefined
        # Instance ID service run on
        @instance = undefined
        # Application ID to run
        @app = undefined
        # Posix user to run
        @user = undefined
        # Service domain
        @domain = 'localhost'
        # Service port
        @port = 4000

    setAccount: (accountId, cb)=>
        state.load accountId, (err, account)=>
            return cb and cb(err) if err
            @on 'state', 'serviceState', accountId
            @account = accountId
            account.add @id, cb

    # Set service application
    setApp: (appId, cb)->
        state.load appId, (err, app)=>
            return cb and cb(err) if err
            @on 'state', 'serviceState', appId
            @app = appId
            app.add @id, cb

    # Set service instance
    setInstance: (instanceId, cb)->
        state.load instanceId, (err, instance)=>
            return cb and cb(err) if err
            @on 'state', 'serviceState', instanceId
            @instance = instanceId
            @user = instance.user
            @address = instance.address
            @home = "/home/#{instance.user}/.cloudpub"
            instance.add @id, cb

    # Submit task to work queue
    submit: (params, cb)->

        if not (@address and @user and @home and @instance and @app)
            return cb and cb(new Error("Service not initialized"))

        params.address = @address
        params.user = @user
        params.home = @home
        
        super params, cb

    # Startup handler
    startup: (cb) ->
        cb and cb(new Error('Not impelemented for this service'))

    # Shutdown handler
    shutdown: (cb) ->
        cb and cb(new Error('Not impelemented for this service'))

    # Install handler
    install: (cb) ->
        cb and cb(new Error('Not impelemented for this service'))

    # Uninstall handler
    uninstall: (cb) ->
        cb and cb(new Error('Not impelemented for this service'))

    
# Init request handlers here
exports.init = (app, cb)->
    # List of services
    app.register 'service', ((entity, cb)->state.query('cloudpub', cb)), ((id, entity, cb)->state.load( id, cb ))
    cb and cb(null)
