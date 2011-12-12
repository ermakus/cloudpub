fs      = require 'fs'
_       = require 'underscore'
form    = require 'express-form'
events  = require 'events'
nconf   = require 'nconf'
account = require './account'

ENV     = require './env'

# Default service object

class Service extends events.EventEmitter

    # Service display name
    name: 'Default Service Name'

    # State: DOWN, MANTAINING or UP
    state: 'down'

    # Source for install
    source: '/home/anton/Projects/cloudpub'

    constructor: (@sid, @account) ->
        if not @sid then throw new Error('SID is not set')
        if not @account then throw new Error('Account is not set')
        @state = nconf.get( "service:#{@sid}:state" ) or "down"
        @home = "/home/#{@account.uid}/#{@sid}"

    save: (cb) ->
        nconf.set( "service:#{@sid}:state", @state )
        nconf.save cb

    # Retreive service info
    info: (cb)->
        info =
            sid:@sid
            name:@name
            state:@state
            domain:"#{@sid}.#{@account.uid}.cloudpub.us"
        cb and cb(null, info)

    # Start service
    start: (params, cb)->
        @state = 'maintain'
        @install params, (err)=>
            return cb and cb(err) if err
            @worker = new Worker( @, 3001 )
            @worker.start (err)=>
                return cb and cb(err) if err
                @state = 'up'
                @save cb

    # Stop service
    stop: (params, cb)->
        @state = 'maintain'
        @uninstall params, (err)=>
            return cb and cb(err) if err or not @worker
            @worker.stop (err)=>
                return cb and cb(err) if err
                @state = 'down'
                @save cb

    install: (params, cb)->
        console.log "Install #{@sid} to #{@home}"
        fs.stat target, (err, dir) =>
            return cb and cb( null ) if not err
                exec "sudo -u #{@account.uid} cp -r #{source} #{target}", (err, stdout, stderr) =>
                if stderr then console.error stderr
                return cb and cb( err ) if err
                @configure params, cb

    configure: (params, cb)->
        preproc __currdir + '/nginx.vhost', @home + '/nginx.vhost', @. =>
            exec "sudo 'ln -s #{@home}/nginx.vhost /etc/nginx/sites-enabled/#{@sid}.#{@account.uid}.conf && service nginx reload'", (err, stdout, stderr) =>
                if stderr then console.error stderr
                cb and cb(err)


    uninstall: (params, cb)->
        console.log "Uninstall #{@home}"
            fs.stat target, (err, dir) ->
                return cb and cb(null) if err
                exec "rm -rf #{target}", (err, stdout, stderr) ->
                    cb and cb( err )


# Preprocess files
preproc = (source, targert, context, cb) ->
    fs.readFile source, (err, cfg) ->
        return cb and cb( err ) if err
        cfg = _.template cfg.toString(), context
        fs.writeFile target, cfg, (err)->
            return cb and cb( err ) if err


class Worker

    constructor: (@service, @port)->

    start: (cb)->
        console.log "Start #{@service.home} on port #{@port}"
        @child = spawn "node", ["server.js", @port], cwd:@service.home
        @child.stderr.on 'data', (data) -> console.error data.toString()
        @child.stdout.on 'data', (data) -> console.log data.toString()
        timer = setTimeout (=>
            timer = null
            cb and cb null ), 100
        @child.on 'exit', (code, signal) ->
            console.log 'child process terminated due to receipt of signal ' + signal
            if not timer
                return cb and cb( null )
            clearTimeout timer
            cb and cb( new Error('Child terminated with signal ' + signal ) )

    stop: (cb)->
        if @child
            console.log "Send kill signal to #{@service.home} on port #{@port}"
            @child.kill('SIGHUP')
            @child = null
        cb and cb( null )

# Service management

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

# Reload all services 
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

