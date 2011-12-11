fs = require 'fs'
exec = require('child_process').exec
spawn = require('child_process').spawn

LAST_PORT = 3001

allocatePort = -> LAST_PORT++

exports.home = (acc, sid) ->
    path = acc.home + '/' + sid
    if path.length < '/home/anton/'.length
        throw new Error("Bad path")
    path

exports.install = (acc, sid, source, cb)->
    target = exports.home acc, sid
    console.log "Install #{source} to #{target}"
    fs.stat target, (err, dir) ->
        return cb and cb( null ) if not err
        exec "git clone #{source} #{target}", (err, stdout, stderr) ->
            cb and cb( err )

exports.uninstall = (acc, sid, cb)->
    target = exports.home acc, sid
    console.log "Uninstall #{target}"
    fs.stat target, (err, dir) ->
        return cb and cb(null) if err
        exec "rm -rf #{target}", (err, stdout, stderr) ->
            cb and cb( err )

WORKERS={}

exports.start = (acc, sid, cb)->
    target = exports.home acc, sid
    port = allocatePort()
    console.log "Start #{target} on port #{port}"

    child = spawn "node", ["server.js", port], cwd:target
    child.stderr.on 'data', (data)->console.error data.toString()
    child.stdout.on 'data', (data)->console.log data.toString()
    console.log child
    WORKERS[ target ] = child
    cb and cb( null, child, port )

exports.stop = (acc, sid, cb)->
    target = exports.home acc, sid
    console.log "Stop #{target}"
    if target in WORKERS
        WORKERS[ target ].kill('SIGTERM')
        delete WORKERS[ target ]
    cb and cb( null )

