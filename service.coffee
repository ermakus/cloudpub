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
        @instance = params.instance

        # Generate SSH vhost
        @submit 'preproc',
            source:__dirname + '/nginx.vhost'
            target: @home + '/vhost'
            context: { service:@, params }
        @submit 'shell',
            command:["sudo", "ln", "-sf", "#{@home}/vhost", "/etc/nginx/sites-enabled/#{@id}.#{@user}.conf"]
        @submit 'shell',
            command:["sudo", "service", "nginx", "reload"]

        @setState 'maintain', "Configuring service", cb


    # Start service
    start: (params, cb)->
        @configure params, (err)=>
            return cb and cb(err) if err
            @install params, cb

    # Stop service
    stop: (params, cb)->
        @setState 'maintain', "Stopping", (err)=>
            return cb and cb(err) if err
            if params.data != 'keep'
                @uninstall params, cb
            else
                @setState 'down', "On maintance", cb

    # Install service files and configure
    install: (params, cb)->
        async.map params.instance, (
            (iid, cb) =>
                @setState 'maintain', "Installing app #{@id} on server #{iid}", (err)->
                    return cb and cb(err) if err
                    state.load iid, 'instance', (err, instance) ->
                        instance.submit 'copy', {source:'~/cloudpub',target:'~/'}
        ), cb

    # Delete service files
    uninstall: (params, cb)->
        @submit 'shell', command:['rm','-rf','~/cloudpub']
        cb and cb(err)

# Init request handlers here
exports.init = (app, cb)->
    # Register default handler
    app.register 'service', (entity, cb) ->
        # Load predefined apps form storage (or create new one)
        async.map ['cloudpub'], ( (id, callback) ->
                # Load entity from storage
                state.load id, 'service', (err, item) ->
                    return callback and callback(err) if err
                    # Load workers from storage
                    async.map item.workers, state.load, (err, workers)->
                        return callback and callback(err) if err
                        item.workers = workers
                        # Fire item callback and pass resolved item
                        callback and callback(null, item)
        ), cb
    cb and cb(null)
