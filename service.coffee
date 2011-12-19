fs      = require 'fs'
_       = require 'underscore'
async   = require 'async'

account  = require './account'
worker   = require './worker'
command  = require './command'
state    = require './state'

# Default service object


exports.Service = class Service extends worker.WorkQueue

    init: ->
        super()
        # Service display name
        @name = 'cloudpub'

        # Source for install
        @source = __dirname

        # Service domain
        @domain = 'cloudpub.us'

        # Instance IDs service run on
        @instance = []

        # User account to run
        @user = 'cloudpub'

    # Configure service
    configure: (params, cb)->
        @user = params.session.uid
        @domain = params.domain or "#{@id}.#{@user}.cloudpub.us"
        @home = "/home/#{@user}/#{@id}"
        if _.isArray params.instance
            @instance = params.instance
        else
            if params.instance
                @instance = [params.instance]
            else
                return cb and cb(new Error("Instance node set") )

#        # Generate SSH vhost
#        @submit 'preproc',
#            source:__dirname + '/nginx.vhost'
#            target: @home + '/vhost'
#            context: { service:@, params }
#        @submit 'shell',
#            command:["sudo", "ln", "-sf", "#{@home}/vhost", "/etc/nginx/sites-enabled/#{@id}.#{@user}.conf"]
#        @submit 'shell',
#            command:["sudo", "service", "nginx", "reload"]

        @setState 'maintain', "App configured", cb


    # Start service
    start: (params, cb)->
        @configure params, (err)=>
            return cb and cb(err) if err
            @install params, cb

    # Stop service
    stop: (params, cb)->
        if params.data != 'keep'
            @uninstall params, cb
        else
            @setState 'down', "On maintance", cb

    # Install service files and configure
    install: (params, cb)->

        process = (id, cb)->
            state.load id, (err, instance) ->
                instance.install params, (err)->
                    cb and cb( err, instance )

        async.forEach @instance, process, (err) =>
            return cb and cb(err) if err
            @setState "maintain", "Installing app #{@id} on servers", cb

    # Delete service files
    uninstall: (params, cb)->
        process = (id, cb)->
            state.load id, (err, instance) ->
                instance.uninstall params, (err)->
                    cb and cb( err, instance )

        async.forEach @instance, process, (err) =>
            return cb and cb(err) if err
            @setState "maintain", "Removing app #{@id} from servers", cb

# Init request handlers here
exports.init = (app, cb)->
    # Register default handler
    app.register 'service', (entity, cb) ->
        # Load predefined apps form storage (or create new one)
        async.map ['cloudpub'], ( (id, callback) ->
                # Load entity from storage
                state.load id, (err, item) ->
                    return callback and callback(err) if err
                    # Load workers from storage
                    async.map item.instance, state.load, (err, instance)->
                        return callback and callback(err, item) if err
                        item.instance = instance
                        # Fire item callback and pass resolved item
                        callback and callback(null, item)
        ), (err, data) ->
                cb and cb(err, data)

    state.create 'cloudpub', 'service', (err, item) ->
        item.save cb
