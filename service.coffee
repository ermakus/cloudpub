fs      = require 'fs'
_       = require 'underscore'
form    = require 'express-form'
events  = require 'events'
nconf   = require 'nconf'
exec    = require('child_process').exec
spawn   = require('child_process').spawn

account = require './account'
worker  = require './worker'

# Default service object

class Service extends events.EventEmitter

    # Service display name
    name: 'Default Service Name'

    # State: DOWN, MANTAINING or UP
    state: 'down'

    # Source for install
    source: '/home/anton/Projects/cloudpub'

    # Service port
    port: 3001

    # Service domain
    domain: 'localhost'

    workers: 0

    # Create instanse of service and load state from the store
    constructor: (@sid, @account) ->
        if not @sid then throw new Error('SID is not set')
        if not @account then throw new Error('Account is not set')
        @state   = nconf.get( "service:#{@sid}:state" ) or "down"
        @port    = nconf.get( "service:#{@sid}:port" ) or 3001
        @workers = nconf.get( "service:#{@sid}:workers" ) or 0
        @domain  = nconf.get( "service:#{@sid}:domain" ) or "#{@sid}.#{@account.uid}.cloudpub.us"
        @home = "/home/#{@account.uid}/#{@sid}"

    # Save service state to store
    save: (cb) ->
        nconf.set( "service:#{@sid}:state",   @state )
        nconf.set( "service:#{@sid}:port",    @port )
        nconf.set( "service:#{@sid}:workers", @workers )
        nconf.set( "service:#{@sid}:domain",  @domain )
        nconf.save cb

    # Change and save state
    setState: (@state, cb) -> @save cb

    # Retreive service info
    info: (cb)->
        info =
            sid:@sid
            name:@name
            state:@state
            domain:@domain
            workers:@workers
            storage:0.0
            bandwith:0.0
        cb and cb(null, info)

    # Start service
    start: (params, cb)->
        @setState 'maintain', (err)=>
            return cb and cb(err) if err
            @install params, (err)=>
                return cb and cb(err) if err
                wrk = @getWorker @workers
                wrk.start (err)=>
                    return cb and cb(err) if err
                    @workers++
                    @setState 'up', cb

    # Stop service
    stop: (params, cb)->
        @setState 'maintain', (err)=>
            return cb and cb(err) if err
            if @workers
                wrk = @getWorker --@workers
                wrk.stop (err)=>
                    return cb and cb(err) if err
                    @uninstall params, (err)=>
                        @setState 'down', cb
            else
                @uninstall params, =>
                    @setState 'down', cb

    # Install service files and configure
    install: (params, cb)->
        console.log "Install #{@sid} to #{@home}"
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
            cmd = "sudo ln -sf #{@home}/vhost /etc/nginx/sites-enabled/#{@sid}.#{@account.uid}.conf && sudo service nginx reload"
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

    getWorker: (num) ->
        wid = "#{@account.uid}-#{@sid}-#{num}"
        new worker.create( wid, @ )
 


# Preprocess config file template
preproc = (source, target, context, cb) ->
    console.log "Preproc #{source} -> #{target}: " + JSON.stringify context
    fs.readFile source, (err, cfg) ->
        return cb and cb( err ) if err
        cfg = _.template cfg.toString(), context
        fs.writeFile target, cfg, (err)->
            cb and cb( err )



# Service management forms and views

SERVICES         = []
SERVICE_COMMANDS = ['start','stop']
SERVICE_DIR      = __dirname + '/wapp'

# Service command forms (passed as 1st param to service methods)

COMMAND_FORMS =
    start: form(
        form.validate("sid").required().is(/^[a-z0-9\.]+$/)
        form.filter("domain").trim().toLower(),
        form.validate("domain").required().is(/^[a-z0-9\.]+$/)
    )
    stop: form(
        form.validate("sid").required().is(/^[a-z0-9\.]+$/)
        form.validate("data").required().is(/^(keep|delete)$/)
    )

# Reload all service configs 
exports.reload = (cb)->
    console.log "Loaded services from #{SERVICE_DIR}"
    fs.readdir SERVICE_DIR, (err, list)->
        if err then return cb and cb( err )
        SERVICES = []
        for file in list
            if match = /(.+)\.coffee/.exec file
                service = require "#{SERVICE_DIR}/#{match[1]}"
                service.sid = match[1]
                SERVICES.push service
        cb and cb( null, SERVICES )

# Create service by SID and bind with account
exports.create = (sid, acc) ->
    for service in SERVICES
        if service.sid == sid
            instance = _.extend( new Service( sid, acc ), service )
            return instance
    null

# Init request handlers here
exports.init = (app, cb)->

    # Return services list with account info
    app.get '/services', account.force_login, (req,resp)->
        count = SERVICES.length
        if not (acc = account.find req.session.uid)
            return resp.render 'services', {error:"Invalid account ID"}
        if req.param('naked',false)
            template = 'services-table'
            layout = false
        else
            template = 'services'
            layout = true
        services = []
        errors = ''
        # Async call each servics info handler
        for service in (SERVICES.map (meta) -> exports.create meta.sid, acc)
            service.info (err, info)->
                if not err
                    services.push info
                else
                    errors += (err.message + "<br/>")
                # Send response when all info collected
                --count or resp.render template, {layout, services, error:errors}

    # Call service command
    app.post '/service/:command', account.ensure_login, (req, resp)->
        if not (acc = account.find req.session.uid)
            return resp.send 'Invalid account ID', 500
        if not (req.params.command in SERVICE_COMMANDS)
            return resp.send 'Invalid service command', 500
        service = exports.create req.param('sid', null), acc
        if not service
            return resp.send 'Invalid service ID', 500
        command = service[ req.params.command ]
        if not command
            return resp.send 'Command not supported', 500

        form = COMMAND_FORMS[ req.params.command ]

        exec_command = (req,resp) ->
           console.log "Exec #{service.sid}.#{req.params.command} " + if req.form then JSON.stringify req.form
           command.call service, req.form, (err) ->
                if err then return resp.send err.message, 500
                resp.send true

        if form
            form req, resp, ->
                if req.form.isValid
                    exec_command req, resp
                else
                    resp.send (req.form.errors.join '</br>'), 500
        else
            exec_command req, resp

    exports.reload cb

