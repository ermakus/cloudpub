fs      = require 'fs'
_       = require 'underscore'
events  = require 'events'
nconf   = require 'nconf'
exec    = require('child_process').exec
spawn   = require('child_process').spawn

account  = require './account'
worker   = require './worker'
command  = require './command'
state    = require './state'

# Default service object


class Service extends state.State

    # Service display name
    name: 'Default Service Name'

    # Source for install
    source: '/home/anton/Projects/cloudpub'

    # Service port
    port: 3001

    # Service domain
    domain: undefined

    workers: 0

    # Create instanse of service and load state from the store
    constructor: (@id, @account) ->
        super('service', @id)
        if not @id then throw new Error('SID is not set')
        if not @account then throw new Error('Account is not set')
        @domain  ?= "#{@id}.#{@account.uid}.cloudpub.us"
        @home = "/home/#{@account.uid}/#{@id}"

    # Retreive service info
    info: (cb)->
        cb and cb(null, @)

    # Start service
    start: (params, cb)->
        @setState 'maintain', (err)=>
            return cb and cb(err) if err
            @install params, (err)=>
                return cb and cb(err) if err
                wrk = @createWorker()
                wrk.exec ['node','~/cloudpub/server.js','4000'] (err)=>
                    return cb and cb(err) if err
                    @setState 'up', cb
                @workers = wrk.id


    # Stop service
    stop: (params, cb)->
        @setState 'maintain', (err)=>
            return cb and cb(err) if err
            if @workers
                wrk = @createWorker()
                wrk.stop (err)=>
                    return cb and cb(err) if err
                    @uninstall params, (err)=>
                        @setState 'down', cb
            else
                @uninstall params, =>
                    @setState 'down', cb

    # Install service files and configure
    install: (params, cb)->
        console.log "Install #{@id} to #{@home}"
        @domain = params.domain
        fs.stat @home, (err, dir) =>
            return cb and cb( null ) if not err
            exec "sudo -u #{@account.uid} cp -r #{@source} #{@home}", (err, stdout, stderr) =>
                if stdout then console.log stdout
                if stderr then console.log stderr
                return cb and cb( err ) if err
                @configure params, cb

    # Configure service (i.e. setup proxy)
    configure: (params, cb)->
        preproc __dirname + '/nginx.vhost', @home + '/vhost', { service:@, params }, (err) =>
            cmd = "sudo ln -sf #{@home}/vhost /etc/nginx/sites-enabled/#{@id}.#{@account.uid}.conf && sudo service nginx reload"
            exec cmd, (err, stdout, stderr) =>
                if stdout then console.log stdout
                if stderr then console.log stderr
                cb and cb(err)


    # Delete service files
    uninstall: (params, cb)->
        console.log "Uninstall #{@home}"
        fs.stat @home, (err, dir) =>
            return cb and cb(null) if err
            exec "rm -rf #{@home}", (err, stdout, stderr) =>
                if stderr then console.log stderr
                cb and cb(err)

    createWorker: ->
        new worker.Worker( @account.uid, 'localhost' )

# Preprocess config file template
preproc = (source, target, context, cb) ->
    console.log "Preproc #{source} -> #{target}: " + JSON.stringify context
    fs.readFile source, (err, cfg) ->
        return cb and cb( err ) if err
        cfg = _.template cfg.toString(), context
        fs.writeFile target, cfg, (err)->
            cb and cb( err )

# Array of available apps
APPS         = []

# Directory with apps
APPS_DIR      = __dirname + '/wapp'

# Reload all application templates to APPS
exports.reload = (cb)->
    console.log "Loaded apps from #{APPS_DIR}"
    fs.readdir APPS_DIR, (err, list)->
        if err then return cb and cb( err )
        APPS = []
        for file in list
            if match = /(.+)\.coffee/.exec file
                app = require "#{APPS_DIR}/#{match[1]}"
                app.id = match[1]
                APPS.push app
        cb and cb( null, APPS )

# Create service by SID and bind with account
exports.create = (appid, acc) ->
    # Seeking for app
    for app in APPS
        if app.id == appid
            # Create service and patch by app
            console.log "Accesing service #{appid}"
            return _.extend( new Service( appid, acc ), app )
    null

# Init request handlers here
exports.init = (app, cb)->
    app.get '/services', account.force_login, (req, resp)->
        resp.render 'service'

    # Return services list with account info
    app.get '/api/services', account.ensure_login, command.list_handler("service", (entity, acc, cb) ->
        # Data callback should return list of items. 
        # Here we create one service for each available app type
        data = APPS.map (app) -> exports.create app.id, acc
        # Final countdown
        count = data.length
        items = []
        errors = ''
        # And call each servics info handler
        for item in data
            item.info (err, info)->
                if not err
                    items.push info
                else
                    errors += (err.message + "<br/>")
                # ..until all info is collected
                unless --count
                    if errors
                        err = new Error(errors)
                    else
                        err = null
                    cb and cb err, items
    )

    # Call service command
    app.post '/api/service/:command', account.ensure_login, command.command_handler("service", (id, acc)->
        # Factory callback should create and init item instance by id and user account
        exports.create id, acc
    )
    exports.reload cb

