async = require 'async'
service = require './service'

exports.Cloudpub = class Cloudpub extends service.Service
       
    startup: (cb) ->
        @submit 'shell', {
            message: "Starting daemon"
            command:["#{@home}/cloudpub/bin/daemon", "-b", "#{@home}/cloudpub", "start", @id,
                     "#{@home}/runtime/bin/node", "#{@home}/cloudpub/server.js", 4000]
        }, cb

    shutdown: (cb) ->
        @submit 'shell', {
            message: "Stop daemon"
            home: "#{@home}/cloudpub"
            command:["#{@home}/cloudpub/bin/daemon", "stop", @id]
        }, cb

    install: (cb) ->
        async.series [
            # Sync service files
            (cb)=> @submit('sync', {
                        message: "Sync service files"
                        source:'/home/anton/Projects/cloudpub'
                        target: "#{@home}/" }, cb),
            # Install service deps
            (cb)=> @submit('shell', {
                        message: "Install node.js runtime"
                        command:["#{@home}/cloudpub/bin/install", "node", "#{@home}/runtime"] }, cb),
        ], cb

    uninstall: (cb) ->
        @submit 'shell', {
            command:['rm','-rf', @home]
        }, cb
