async = require 'async'
service = require './service'

exports.Cloudpub = class Cloudpub extends service.Service
       
    startup: (cb) ->
        @submit({
            task:    "shell"
            message: "Starting daemon"
            command: ["#{@home}/cloudpub/bin/daemon",
                      "-b", "#{@home}/cloudpub",
                      "start", @id, "#{@home}/runtime/bin/node",
                      "#{@home}/cloudpub/server.js", 4000]
            success:
                state:'up'
                message: 'Online'
        }, cb)

    shutdown: (cb) ->
        @submit({
            task:    "shell"
            message: "Stop daemon"
            home:    "#{@home}/cloudpub"
            command:["#{@home}/cloudpub/bin/daemon", "stop", @id]
            success:
                state:   'down'
                message: 'Terminated'
        }, cb)

    install: (cb) ->
        async.series( [
                # Sync service files
                (cb) => @submit({
                            task: 'sync'
                            message: "Sync service files"
                            source:'/home/anton/Projects/cloudpub'
                            target: "#{@home}/"
                            success:
                                state:'maintain'
                                message: 'Service installed'
                        }, cb),
                # Install service deps
                (cb) => @submit({
                            task: 'shell'
                            message: "Install node.js runtime"
                            command:["#{@home}/cloudpub/bin/install", "node", "#{@home}/runtime"]
                            success:
                                state:'maintain'
                                message: 'Runtime compiled'
                        }, cb)
            ], cb)

    uninstall: (cb) ->
        @submit({
            task: 'shell'
            command:['rm','-rf', @home]
            success:
                state:'down'
                message: 'Service uninstalled'
        }, cb)

