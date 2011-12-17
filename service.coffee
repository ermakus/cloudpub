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


exports.Service = class Service extends worker.WorkQueue

    # Service display name
    name: 'Default Service Name'

    # Source for install
    source: '/home/anton/Projects/cloudpub'

    # Service port
    port: 3001

    # Service domain
    domain: undefined

    # Instance ID service run on
    instance: 'localhost'

    # User account to run
    user: 'root'

    # Create instanse of service and load state from the store
    constructor: (entity, id) ->
        super(entity, id)
        @domain  ?= "#{@id}.#{@account.uid}.cloudpub.us"
        @home = "/home/#{@account.uid}/#{@id}"

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

# Init request handlers here
exports.init = (app, cb)->
    # Register default handler
    app.register 'service'
    cb and cb(null)
