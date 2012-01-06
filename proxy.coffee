async = require 'async'
service = require './service'

exports.Proxy = class Proxy extends service.Service
    
    init: ->
        super()
        @name = 'cloudpub-proxy'

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
                message: "Start Proxy"
                state:   "maintain"
                command: ["daemon","start", @id, "./sbin/nginx", "-c", "#{@home}/conf/nginx.conf" ]
                success:
                    state:'up'
                    message: 'Online'
            }], cb

    shutdown: (params, cb) ->
        if typeof(params) == 'function'
            cb = params
            params = {}

        @submit([{
                entity:  "shell"
                package: "worker"
                message: "Stop Proxy"
                state:   "maintain"
                context:
                    id: @instance
                command:["daemon", "stop", @id]
                success:
                    state:   'down'
                    message: 'Offline'
            }], cb)

    install: (cb) -> @submit( {
                entity:  'shell'
                package: 'worker'
                message: "Compile proxy"
                state:   "maintain"
                home: @home
                command:["install-proxy", @home]
                success:
                    state: "maintain"
                    message: "Proxy installed"
           }, cb)

    uninstall: (cb) -> @submit({
                state: 'maintain'
                message: 'Uninstall proxy'
                entity:  'shell'
                package: 'worker'
                command:['kya','params']
                success:
                    state:'down'
                    message: 'Proxy uninstalled'
            }, cb)

