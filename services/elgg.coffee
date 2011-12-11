# Service management script
_ = require 'underscore'
fs = require 'fs'
form = require 'express-form'
exec = require('child_process').exec

CONFIG_DIR = '/tmp'

SOURCE='https://github.com/Elgg/Elgg.git'

git_clone = (source, target, cb) ->
    exec "git clone #{source} #{target}", (err, stdout, stderr) ->
        cb and cb( err )

rm = (target, cb)->
    exec "rm -rf #{target}", (err, stdout, stderr) ->
        cb and cb( err )

exports.state = "maintain"

# Resolve service info with given account uid
exports.info = (acc, cb) ->

    service =
        sid: exports.sid
        name: 'Elgg Social Network'
        domain: 'localhost'
        home: acc.home + '/' + exports.sid
        state: exports.state

    cb and cb( null, service )

# Define form for configure service
exports.configure_form = form(
    form.filter("domain").trim().toLower(),
    form.validate("domain").required().is(/^[a-z0-9.]+$/)
)


# Install service for uid account
exports.start = (acc, params, cb)->
    exports.info acc, (err, service)->
        if err then return cb and cb(err)
        git_clone SOURCE, service.home, (err)->
            if err then return cb and cb(err)
            fs.readFile __dirname + '/elgg.apache.conf', (err, cfg) ->
                if err then return cb and cb(err)
                cfg = _.template cfg.toString(), {service:service,account:acc}
                fs.writeFile "#{service.home}/#{acc.uid}.#{service.sid}.conf", cfg, (err)->
                    cb and cb( err )

# Uninstall service for uid account
exports.stop = (acc, params, cb)->
    exports.info acc, (err, service)->
        if err then return cb and cb(err)
        rm service.home, (err)->
            cb and cb( err )
