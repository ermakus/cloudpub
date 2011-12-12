fs = require 'fs'
exec = require('child_process').exec
spawn = require('child_process').spawn
_ = require 'underscore'

LAST_PORT = 3001

allocatePort = -> LAST_PORT++

exports.home = (acc, sid) ->
    path = acc.home + '/' + sid
    if path.length < '/home/anton/'.length
        throw new Error("Bad path")
    path

# Install service for uid account
exports.install = (acc, sid, source, cb)->
    target = exports.home acc, sid
    console.log "Install #{source} to #{target}"
    fs.stat target, (err, dir) ->
        return cb and cb( null ) if not err
        exec "install -C -o #{acc.uid} -g #{acc.uid} #{source} #{target}", (err, stdout, stderr) ->
            return cb and cb( err ) if err
            exports.configure acc, sid, cb

# Configure service
exports.configure = (acc, sid, cb)->
    target = exports.home acc, sid
    fs.readFile __dirname + "/wapp/#{sid}.vhost", (err, cfg) ->
        return cb and cb(err) if err
        cfg = _.template cfg.toString(), {sid:sid,account:acc}
        fs.writeFile "/etc/nginx/sites-enabled/#{acc.uid}.#{sid}.conf", cfg, (err)->
            return cb and cb( err ) if err
            exec "service nginx reload", (err, stdout, stderr) ->
                cb and cb(err)

# Uninstall service
exports.uninstall = (acc, sid, cb)->
    target = exports.home acc, sid
    console.log "Uninstall #{target}"
    fs.stat target, (err, dir) ->
        return cb and cb(null) if err
        exec "rm -rf #{target}", (err, stdout, stderr) ->
            cb and cb( err )

WORKERS = {}
# Start worker
exports.start = (acc, sid, cb)->
    target = exports.home acc, sid
    port = allocatePort()
    console.log "Start #{target} on port #{port}"

    child = spawn "node", ["server.js", port], cwd:target
    child.stderr.on 'data', (data) -> console.error data.toString()
    child.stdout.on 'data', (data) -> console.log data.toString()
    child.on 'exit', (code, signal) ->
        console.log 'child process terminated due to receipt of signal ' + signal

    WORKERS[ target ] = child
    cb and cb( null, child, port )

# Stop worker
exports.stop = (acc, sid, cb)->
    target = exports.home acc, sid
    if target of WORKERS
        console.log "Send kill signal to #{target}"
        WORKERS[ target ].kill('SIGHUP')
        delete WORKERS[ target ]
    cb and cb( null )

