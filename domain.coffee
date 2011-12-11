dns = require 'dns'
form = require 'express-form'

CLOUD_ADDRS = ['178.63.168.18']

in_cloud = (addrs)->
    for addr in addrs
        if addr not in CLOUD_ADDRS then return false
    true

validate_domain_form = form(
    form.filter("domain").trim().toLower(),
    form.validate("domain").required().is(/^(?=.{1,255}$)[0-9A-Za-z](?:(?:[0-9A-Za-z]|\b-){0,61}[0-9A-Za-z])?(?:\.[0-9A-Za-z](?:(?:[0-9A-Za-z]|\b-){0,61}[0-9A-Za-z])?)*\.?$/)
)


exports.init = (app, cb) ->
    app.get '/resolve/:domain', validate_domain_form, (req, resp) ->

        domain =
           name: req.params.domain
           valid: false
           help: 'Invalid domain name'
 
        if not req.form.isValid
            return resp.send domain
        
        dns.resolve4 req.form.domain, (err, addrs) ->
            domain.addrs = addrs
            domain.valid = not err
            if err
                if err.code == 'ENOTFOUND'
                    domain.error = 'Domain not found'
                    domain.help = "You can <a href='#'>Buy and Use</a> this domain name"
                else
                    domain.error = 'Invalid domain name'
                    domain.help  = "Type correct domain name for service"
            else
                domain.help = "Active domain"
                
                if not in_cloud domain.addrs
                    domain.help += "<br/>Please change A records from " + domain.addrs.join(' ') + " to " + CLOUD_ADDRS.join(' ')
                else
                    domain.help += "<br/>Correctly configured"
            resp.send domain

    cb and cb(null)
