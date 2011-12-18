form    = require 'express-form'
account = require './account'

ALLOWED_COMMANDS = ['start','stop']

COMMAND_FORMS =
    service_start: form(
        form.validate("id").required().is(/^[a-z0-9\.]+$/)
        form.filter("domain").trim().toLower(),
        form.validate("domain").required().is(/^[a-z0-9\.]+$/)
        form.validate("instance").required()
    )
    service_stop: form(
        form.validate("id").required().is(/^[a-z0-9\.]+$/)
        form.validate("data").required().is(/^(keep|delete)$/)
    )
    instance_start: form(
        form.validate("id").required().is(/^[a-z0-9\.\-]+$/)
        form.validate("cloud").required().is(/^(ec2|ssh)$/)
        form.filter("user").trim().toLower(),
        form.validate("user").is(/^[a-z0-9]+$/)
        form.filter("address").trim().toLower(),
        form.validate("address").is(/^[a-z0-9\.]+$/)
    )
    instance_stop: form(
        form.validate("id").required().is(/^[a-z0-9\.\-]+$/)
        form.validate("mode").required().is(/^(maintain|shutdown)$/)
    )

#
# Return closure with function of entity command handler
#
exports.handler = (entity, factory)->

    return (req, resp)->
        if not (acc = account.find req.session.uid)
            return resp.send 'Invalid account ID', 500
        if not (req.params.command in ALLOWED_COMMANDS)
            return resp.send 'Invalid command', 500

       
        factory req.param('id', null), entity, (err, service)->
            if err
                return resp.send err.message, 500

            if not service
                return resp.send 'Invalid service ID', 500

            command = service[ req.params.command ]
            if not command
                return resp.send 'Command not supported', 500

            form = COMMAND_FORMS[ entity + '_' + req.params.command ]

            exec_command = (req,resp) ->
               console.log "Exec #{req.params.command} on #{entity} " + if req.form then JSON.stringify req.form
               if req.form
                    req.form.session = req.session
               else
                    req.form = session:req.session
               command.call service, req.form, (err) ->
                    if err then return resp.send err.message, 500
                    resp.send service
            if form
                form req, resp, ->
                    if req.form.isValid
                        exec_command req, resp
                    else
                        resp.send (req.form.errors.join '\n'), 500
            else
                exec_command req, resp

