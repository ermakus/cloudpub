async = require 'async'
service = require './service'

exports.Cloudpub = class Cloudpub extends service.Service
       
    startup: (cb) ->
        @submit({
            entity:  "shell"
            package: "worker"
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
            entity:  "shell"
            package: "worker"
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
                            entity: 'sync'
                            package: "worker"
                            message: "Sync service files"
                            source:'/home/anton/Projects/cloudpub'
                            target: "#{@home}/"
                            success:
                                state:'maintain'
                                message: 'Service installed'
                        }, cb),
                # Install service deps
                (cb) => @submit({
                            entity:  'shell'
                            package: 'worker'
                            message: "Install node.js runtime"
                            command:["#{@home}/cloudpub/bin/install", "node", "#{@home}/runtime"]
                            success:
                                state:'maintain'
                                message: 'Runtime compiled'
                        }, cb)
            ], cb)

    uninstall: (cb) ->
        @submit({
            entity:  'shell'
            package: 'worker'
            command:['rm','-rf', @home]
            success:
                state:'down'
                message: 'Service uninstalled'
        }, cb)

