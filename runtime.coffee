async = require 'async'
service = require './service'

exports.Runtime = class Runtime extends service.Service
    
    init: ->
        super()
        @name = 'cloudpub-runtime'

    startup: (cb) ->
        @submit({
            entity:  "shell"
            package: "worker"
            message: "Starting daemon"
            state:   "maintain"
            command: ["#{@home}/bin/daemon",
                      "-b", @home,
                      "start", @id, "#{@home}/sbin/nginx"]
            success:
                state:'up'
                message: 'Online'
        }, cb)

    shutdown: (cb) ->
        @submit({
            entity:  "shell"
            package: "worker"
            message: "Stop daemon"
            state:   "maintain"
            home:    @home
            command:["#{@home}/bin/daemon", "stop", @id]
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
                            state:   "maintain"
                            source: __dirname + "/bin"
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
                            state:   "maintain"
                            command:["#{@home}/bin/install", @home]
                            success:
                                state:'maintain'
                                message: 'Runtime compiled'
                        }, cb)
            ], cb)

    uninstall: (cb) ->
        @submit({
            state: 'maintain'
            message: 'Uninstall service'
            entity:  'shell'
            package: 'worker'
            command:['rm','-rf', @home]
            success:
                state:'down'
                message: 'Service uninstalled'
        }, cb)

