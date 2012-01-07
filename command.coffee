async   = require 'async'
fs      = require 'fs'
form    = require 'express-form'
account = require './account'
state   = require './state'
settings = require './settings'

ENTITY_NEW       = 'new'
ALLOWED_COMMANDS = ['start','stop']

COMMAND_FORMS =
    app_start: form(
        form.validate("command").required()
        form.validate("id").required().is(/^[a-zA-Z0-9\-\.]+$/)
        form.filter("source").trim().toLower(),
        form.validate("source").required().is(/^[a-z0-9\.\-\_]+$/)
        form.filter("domain").trim().toLower(),
        form.validate("domain").required().is(/^[a-z0-9\.]+$/)
        form.validate("instance").required()
    )
    app_stop: form(
        form.validate("command").required()
        form.validate("id").required().is(/^[a-zA-Z0-9\-\.]+$/)
        form.validate("data").required().is(/^(keep|delete)$/)
    )
    instance_start: form(
        form.validate("command").required()
        form.validate("id").required().is(/^[a-zA-Z0-9\.\-]+$/)
        form.filter("cloud").trim().toLower()
        form.filter("user").trim().toLower()
        form.validate("user").is(/^[a-z0-9]+$/)
        form.validate("port").is(/^[0-9]+$/)
        form.filter("address").trim().toLower()
        form.validate("address").is(/^[a-z0-9\.]+$/)
    )
    instance_stop: form(
        form.validate("command").required()
        form.validate("id").required().is(/^[a-zA-Z0-9\.\-]+$/)
        form.validate("data").required().is(/^(keep|delete)$/)
    )
    service_start: form(
        form.validate("command").required()
    )
    service_stop: form(
        form.validate("command").required()
    )
    cloudfu_start: form(
        form.validate("command").required()
        form.validate("instance").required()
    )
 
# Execute command contained in HTTP request
execCommand = (entity, factory, req,resp) ->
    # Create new entity if special ID
    if req.params.id == ENTITY_NEW
        req.params.id = null

    # Override some params
    req.form ||= {}
    req.form.id = req.params.id
    req.form.account = req.session.uid

    # Call factory function that create object
    factory req.form, entity, (err, obj) ->
        if err
            return resp.send err.message, 500

        if not obj
            return resp.send 'Invalid entity', 500

        command = obj[ req.param("command") ]
        if not command
            return resp.send 'Command not supported', 500

        exports.log.info "Exec #{req.param("command")} on #{entity} " + if req.form then JSON.stringify req.form

        async.series [
            # Call stop on object first. This will clear object queue
            (cb)-> obj.stop( cb )
            # Execute command on object.
            # Command should fill queue by tasks
            (cb)->
                command.call obj, req.form, (err) ->
                    if err
                        exports.log.error "Command error: ", err
                        return resp.send err.message, 500
                    # Send object state to client as JSON
                    obj._children = undefined
                    resp.send obj
                    cb(null)
            # Start object queue again
            (cb)-> obj.start(cb)
        ], (err)->
            if err
                exports.console.error "Command start/stop error", err

#
# Return anonymous function to handle API command
#
exports.handler = handler = (entity, factory)->

    return (req, resp)->
        if not (req.param("command") in ALLOWED_COMMANDS)
            return resp.send 'Invalid command', 500
        if not req.params.id
            return resp.send 'Invalid entity ID', 500
            
        form = COMMAND_FORMS[ entity + '_' + req.param("command") ]
        if form
            form req, resp, ->
                if req.form.isValid
                    execCommand entity, factory, req, resp
                else
                    resp.send (req.form.errors.join '\n'), 500
        else
            resp.send "Form for #{entity} is not defined", 500


# Return anonymous function that used to create CRUD REST API handlers
exports.register = (app)->

    # Register entity CRUD handlers
    # Entity name, optional list and item callbacks
    return (entity, list, item)->
        
        list ?= state.query
        item ?= (params, entity, cb) -> state.load( params.id, entity, cb )
    
        # HTML page view
        app.get '/' + entity, account.force_login, (req, resp)->
            resp.render entity, {pubkey:settings.PUBLIC_KEY}

        # API query handler
        app.get '/api/' + entity, account.ensure_login, (req, resp)->
            params = {}
            # Pass current account ID to query params
            params.account = req.session.uid
            list entity, params, (err, data)->
                if err
                    resp.send err.message, 500
                else
                    resp.send data

        # API command handler
        app.post '/api/' + entity + '/:id', account.ensure_login,
            # Default command handler
            handler entity, (id, entity, cb) ->
                # Create or load instance
                item id, entity, cb

