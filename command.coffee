async   = require 'async'
fs      = require 'fs'
form    = require 'express-form'
account = require './account'
state   = require './state'
settings = require './settings'

ENTITY_NEW       = 'new'

COMMAND_FORMS =
    service_launch: form(
        form.validate("command").required()
        form.validate("id").required().is(/^[a-zA-Z0-9\-\.]+$/)
        form.filter("name").trim().toLower(),
        form.validate("name").required().is(/^[a-z0-9\.\-\_]+$/)
        form.filter("source").trim(),
        form.filter("domain").trim().toLower(),
        form.validate("domain").required().is(/^[a-z0-9\.]+$/)
        form.validate("port").is(/^(([0-9]+)|auto)$/)
        form.validate("instance").required()
    )
    service_stop: form(
        form.validate("command").required()
        form.validate("id").required().is(/^[a-zA-Z0-9\-\.]+$/)
        form.validate("data").required().is(/^(keep|delete)$/)
    )
    instance_launch: form(
        form.validate("command").required()
        form.validate("id").required().is(/^[a-zA-Z0-9\.\-]+$/)
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
    # Disabled on production
    __cloudfu_start: form(
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
            settings.log.error "Can't create command target: #{req.form.id} (#{entity})", err.message
            return resp.send err.message, 500

        if not obj
            return resp.send 'Invalid entity', 500

        command = obj[ req.param("command") ]
        settings.log.info "Exec #{req.param("command")} on #{entity} " + if req.form then JSON.stringify req.form
        if not command
            return resp.send 'Command not supported', 500

        command.call obj, req.form, (err) ->
            if err
                settings.log.error "REST command error", err.message
                return resp.send err.message, 500
            # Send object state to client as JSON
            settings.log.info "Command executed"
            resp.send obj

#
# Return anonymous function to handle API command
#
exports.handler = handler = (entity, factory)->
    # Handler function
    return (req, resp)->
        command = req.param("command")
        if not command
            return resp.send 'Invalid command', 500
        if not req.params.id
            return resp.send 'Invalid entity ID', 500
        form = COMMAND_FORMS[ entity + '_' + command ]

        if form
            # Validate form
            form req, resp, ->
                if req.form.isValid
                    # Execute command
                    execCommand entity, factory, req, resp
                else
                    settings.log.warn "Validation error", req.form.errors
                    resp.send (req.form.errors.join '\n'), 500
        else
            settings.log.error "Invalid command", command
            resp.send "Command  #{command} is not allowed", 500


# Return anonymous function that used to create CRUD REST API handlers
exports.register = (app)->

    # Register entity CRUD handlers
    # Entity name, optional list and item callbacks
    return (entity, list, item)->

        list ?= state.query
        item ?= state.loadOrCreate

        # HTML page view
        app.get '/' + entity, account.force_login, (req, resp)->
            resp.render entity

        # API query handler
        app.get '/api/' + entity, account.ensure_login, (req, resp)->
            params = {}
            # Pass current account ID to params
            params.account = req.session.uid
            list entity, params, (err, items)->
                if err
                    settings.log.error "REST query error", err.message
                    resp.send err.message, 500
                else
                    # Send data
                    resp.send items

        # API command handler
        app.post '/api/' + entity + '/:id', account.ensure_login,
            # Default command handler
            handler entity, (id, entity, cb) ->
                # Create or load instance
                item id, entity, cb

