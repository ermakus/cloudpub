fs      = require 'fs'
_       = require 'underscore'
async   = require 'async'

account  = require './account'
worker   = require './worker'
command  = require './command'
state    = require './state'

# Default service object


exports.App = class App extends state.State

    init: ->
        super()
        # Service display name
        @name = 'cloudpub'

        # Service domain
        @domain = 'cloudpub.us'

        # Instance IDs service run on
        @service = []

    # Configure service
    configure: (params, cb)->
        @domain = params.domain or "#{@id}.#{@user}.cloudpub.us"
        if _.isArray params.instance
            @instance = params.instance
        else
            if params.instance
                @instance = [params.instance]
            else
                return cb and cb(new Error("Instance node set") )

        @setState 'maintain', "App configured", cb


    # Start service
    start: (params, cb)->
        async.series [
            ((cb)=>@configure params, cb),
            ((cb)=>@setState "maintain", "Installing to servers", cb),
            ((cb)=>@runEach @install, params, cb)
            ((cb)=>@runEach @startup, params, cb)
        ], cb

    # Stop service
    stop: (params, cb)->
        params ?= {}
        if params.data != 'keep'
            async.series [
                ((cb)=>@setState "maintain", "Uninstalling from servers", cb),
                ((cb)=>@runEach @shutdown, params, cb),
                ((cb)=>@runEach @uninstall, params, cb)
            ], cb
        else
            async.series [
                ((cb)=>@setState "maintain", "Maintaince", cb),
                ((cb)=>@runEach @shutdown, params, cb)
            ], cb

    # Run command for each instance
    runEach: (method, params, cb)->

        service = @

        process = (id, cb)->
            state.load id, (err, instance) ->
                params.instance = instance
                method.call service, params, instance, (err)->
                    cb and cb( err, instance )

        async.forEach @instance, process, cb

    startup: ( params, instance, cb) ->
        cb and cb(null)

    shutdown: ( params, instance, cb) ->
        instance.stopWork cb

    install: ( params, instance, cb) ->
        cb and cb(null)

    uninstall: ( params, instance, cb ) ->
        cb and cb(null)


# Init request handlers here
exports.init = (app, cb)->
    # Register default handler
    list = (entity, cb) ->
        # Load predefined apps form storage (or create new one)
        state.query 'cloudpub', (err, items) ->
                return cb and cb(err) if err
                # For each service
                async.map items, ((item, callback)->
                    # Resolve instances from storage
                    async.map item.instance, state.load, (err, instance)->
                        return callback and callback(err, item) if err
                        item.instance = instance
                        # Fire item callback and pass resolved item
                        callback and callback(null, item)
                ), cb

    app.register 'service', list

    state.create 'cloudpub', 'cloudpub', (err, item) ->
        item.save cb
