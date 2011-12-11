fs      = require 'fs'
account = require './account'

SERVICES = []
SERVICE_COMMANDS = ['start','stop']
SERVICE_DIR = __dirname + '/services'

# Reload all services 
exports.reload = (cb)->
    fs.readdir SERVICE_DIR, (err, list)->
        if err then return cb and cb( err )
        SERVICES = []
        for file in list
            if match = /(.+)\.coffee/.exec file
                service = require "#{SERVICE_DIR}/#{match[1]}"
                service.sid = match[1]
                SERVICES.push service
        cb and cb( null, SERVICES )

# Get service by SID
exports.find = (sid) ->
    for service in SERVICES
        if service.sid == sid then return service
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
        for service in SERVICES
            service.info acc, (err, info)->
                if not err
                    services.push info
                else
                    errors += (err.message + "<br/>")
                # Send response when all info collected
                --count or resp.render template, {layout, services, error:errors}

    # Call service command
    app.get '/service/:command', account.ensure_login, (req, resp)->
        service = exports.find req.param('sid', null)
        if not service
            return resp.send 'Invalid service ID', 500
        if not (acc = account.find req.session.uid)
            return resp.send 'Invalid account ID', 500
        if not (req.params.command in SERVICE_COMMANDS)
            return resp.send 'Invalid service command', 500
        command = service[ req.params.command ]
        if not command
            return resp.send 'Command not supported', 500

        form = service[ req.params.command + "_form" ]
 
        exec_command = (req,resp) ->
           console.log "Exec #{service.sid}.#{req.params.command}"
           command acc, req.form, (err) ->
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

