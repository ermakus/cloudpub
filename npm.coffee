async = require 'async'
service = require './service'

# This class implements npm packaged service
exports.Npm = class Npm extends service.Service

    configure: (params, cb)->
        @source = params.source or @source
        if not @source then return cb and cb(new Error('Source not set'))
        super params, cb

    startup: (params, cb) ->
        if typeof(params) == 'function'
            cb = params
            params = {}

        async.series([
            # Start service as daemon
            (cb) =>
                @submit({
                    entity:  "shell"
                    package: "worker"
                    message: "Starting daemon"
                    state:   "maintain"
                    home:    @home
                    command: ["#{@home}/bin/daemon",
                              "-b", @home,
                              "start", @id, "./bin/node", "./bin/npm", "-g", "--prefix", @home, "start", @source ]
                    success:
                        state:'up'
                        message: 'Online'
                    }, cb)
            # Configure proxy
            (cb) =>
                @submit({
                    entity:  "shell"
                    package: "worker"
                    message: "Attach to proxy"
                    state:   "maintain"
                    home: @home
                    context:
                        id: @id
                        home: @home
                        port: @port
                        domain: @domain
                        default: false
                        services: "server localhost:4000;" # FIXME
                    command: ['domain','enable']
                    success:
                        state:'up'
                        message: 'Online public'
                    }, cb)
            ], cb) # identation!

    shutdown: (params, cb)->
        if typeof(params) == 'function'
            cb = params
            params = {}
        
        async.series [
            (cb) =>
                @submit({
                    entity:  "shell"
                    package: "worker"
                    message: "Detach from proxy"
                    state:   "maintain"
                    home: @home
                    context:
                        id: @id
                        home: @home
                        port: @port
                        domain: @domain
                        default: false
                        services: "server localhost:4000;" # FIXME
                    command: ['domain','enable']
                    success:
                        state:'maintain'
                        message: 'Domain parked'
                    }, cb)
 
            (cb) =>
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
            ], cb

    install: (cb) ->
        @submit({
            entity: 'shell'
            package: "worker"
            message: "Install app"
            state:   "maintain"
            home: @home
            command:["./bin/node", './bin/npm', "--force", "-g", "--prefix", @home, 'install', @source]
            success:
                state:'up'
                message: 'App installed'
        }, cb)

    uninstall: (cb) ->
        @submit({
            state: 'maintain'
            message: "Uninstall app"
            entity:  'shell'
            package: 'worker'
            home: @home
            command:["./bin/node", './bin/npm', "-g", "--prefix", @home, 'uninstall', @source]
            success:
                state:'down'
                message: 'App uninstalled'
        }, cb)

