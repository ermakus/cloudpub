async = require 'async'
service = require './service'

exports.Runtime = class Runtime extends service.Service
    
    init: ->
        super()
        @name = 'cloudpub-runtime'

    startup: (params, cb) ->
        if typeof(params) == 'function'
            cb = params
            params = {}
      
        @submit [
            {
                entity:  "shell"
                package: "worker"
                message: "Configure proxy"
                state:   "maintain"
                home: @home
                context:
                    id: @id
                    home: @home
                    port: @port
                    domain: @domain
                    default: true
                    services: null
                command: ['domain','enable']
                success:
                    state:'maintain'
                    message: 'Proxy configured'
            },
            {
                entity:  "shell"
                package: "worker"
                message: "Start Cloudpub"
                state:   "maintain"
                home: @home
                context:
                    port: @port+1
                    domain: @domain
                command: ["daemon", "-b", @home, "start", @id,
                          "node", "./lib/node_modules/cloudpub/server.js"]
                success:
                    state:'maintain'
                    message: 'Started'
            },
            {
                entity:  "shell"
                package: "worker"
                message: "Start Proxy"
                state:   "maintain"
                home: @home
                command: ["#{@home}/sbin/nginx", "-c", "#{@home}/conf/nginx.conf" ]
                success:
                    state:'up'
                    message: 'Online'
            }
        ], cb


    shutdown: (params, cb) ->
        if typeof(params) == 'function'
            cb = params
            params = {}

        @submit([
            {
                entity:  "shell"
                package: "worker"
                message: "Stop Cloudpub"
                state:   "maintain"
                home: @home
                command:["daemon", "stop", @id]
                success:
                    state:   'down'
                    message: 'Terminated'
            },
            {
                entity:  "shell"
                package: "worker"
                message: "Stop Proxy"
                state:   "maintain"
                home: @home
                command:["daemon", "stop", @id]
                success:
                    state:   'down'
                    message: 'Offline'
            }
         ], cb)

    install: (cb) ->
        async.series( [
                # Sync bin folder
                (cb) => @submit({
                            entity: 'sync'
                            package: "worker"
                            message: "Sync service files"
                            state:   "maintain"
                            source: __dirname + "/bin"
                            home: @home
                            target: "#{@home}/" # Slash important!
                            success:
                                state:'maintain'
                                message: 'Service installed'
                        }, cb),
                # Install runtime
                (cb) => @submit({
                            entity:  'shell'
                            package: 'worker'
                            message: "Compile node runtime"
                            state:   "maintain"
                            home: @home
                            command:["install", @home]
                            success:
                                state:'maintain'
                                message: 'Runtime compiled'
                        }, cb)
                # Install cloudpub
                (cb) => @submit({
                            entity: 'shell'
                            package: "worker"
                            message: "Install cloudpub"
                            state:   "maintain"
                            home: @home
                            command:["./bin/node", './bin/npm', "-g", "--prefix", @home, 'install', __dirname]
                            success:
                                state:'maintain'
                                message: 'Cloudpub installed'
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

