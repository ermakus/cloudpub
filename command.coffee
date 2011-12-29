fs      = require 'fs'
form    = require 'express-form'
account = require './account'
state   = require './state'

ENTITY_NEW       = 'new'
ALLOWED_COMMANDS = ['startup','shutdown']
PUBLIC_KEY_FILE = "/home/anton/.ssh/id_rsa.pub"

try
    PUBLIC_KEY = fs.readFileSync( PUBLIC_KEY_FILE )
catch e
    PUBLIC_KEY = "Not found - please run ssh-keygen"

COMMAND_FORMS =
    app_startup: form(
        form.validate("id").required().is(/^[a-z0-9\-\.]+$/)
        form.filter("source").trim().toLower(),
        form.validate("source").required().is(/^[a-z0-9\.\-\_]+$/)
        form.filter("domain").trim().toLower(),
        form.validate("domain").required().is(/^[a-z0-9\.]+$/)
        form.validate("instance").required()
    )
    app_shutdown: form(
        form.validate("id").required().is(/^[a-z0-9\-\.]+$/)
        form.validate("data").required().is(/^(keep|delete)$/)
    )
    instance_startup: form(
        form.validate("id").required().is(/^[a-z0-9\.\-]+$/)
        form.validate("cloud").required().is(/^(ec2|ssh)$/)
        form.filter("user").trim().toLower(),
        form.validate("user").is(/^[a-z0-9]+$/)
        form.filter("address").trim().toLower(),
        form.validate("address").is(/^[a-z0-9\.]+$/)
    )
    instance_shutdown: form(
        form.validate("id").required().is(/^[a-z0-9\.\-]+$/)
        form.validate("data").required().is(/^(keep|delete)$/)
    )

# Execute command in HTTP request
exec_command = (entity, factory, req,resp) ->
    # Create new entity if special ID
    if req.params.id == ENTITY_NEW
        req.params.id = null

    req.form ||= {}
    req.form.id = req.params.id
    req.form.account = req.session.uid

    factory req.form, entity, (err, obj) ->
        if err
            return resp.send err.message, 500

        if not obj
            return resp.send 'Invalid entity', 500

        command = obj[ req.params.command ]
        if not command
            return resp.send 'Command not supported', 500

        console.log "Exec #{req.params.command} on #{entity} " + if req.form then JSON.stringify req.form
       
        command.call obj, req.form, (err) ->
            if err
                return resp.send err.message, 500

            resp.send obj

#
# Return closure of entity command handler
#
exports.handler = handler = (entity, factory)->

    return (req, resp)->

        if not (req.params.command in ALLOWED_COMMANDS)
            return resp.send 'Invalid command', 500
        if not req.params.id
            return resp.send 'Invalid entity ID', 500
            
        form = COMMAND_FORMS[ entity + '_' + req.params.command ]
        if form
            form req, resp, ->
                if req.form.isValid
                    exec_command entity, factory, req, resp
                else
                    resp.send (req.form.errors.join '\n'), 500
        else
            exec_command entity, factory, req, resp



# Return closure to create CRUD REST handlers
exports.register = (app)->

    # Register entity CRUD handlers
    # Entity name, optional list and item callbacks
    return (entity, list, item)->
        
        list ?= state.query
        item ?= (params, entity, cb) -> state.load( params.id, entity, cb )
    
        # HTML page view
        app.get '/' + entity, account.force_login, (req, resp)->
            resp.render entity, {pubkey:PUBLIC_KEY}

        # API query handler
        app.get '/api/' + entity, account.ensure_login, (req, resp)->
            list entity, (err, data)->
                if err
                    resp.send err.message, 500
                else
                    resp.send data

        # API command handler
        app.post '/api/' + entity + '/:id/:command', account.ensure_login,
            # Default command handler
            handler entity, (id, entity, cb) ->
                # Create or load instance
                item id, entity, cb

