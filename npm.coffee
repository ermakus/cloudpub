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

    shutdown: (params, cb) ->
        if typeof(params) == 'function'
            cb = params
            params = {}

        async.series [
            (cb) => @stop( cb )
            (cb) => @submit({
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
            (cb) => @start( cb )
        ], cb

    install: (cb) ->
        @submit({
            entity: 'shell'
            package: "worker"
            message: "Installing app: #{@source}"
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
            message: "Uninstall app: #{@source}"
            entity:  'shell'
            package: 'worker'
            home: @home
            command:["./bin/node", './bin/npm', "-g", "--prefix", @home, 'uninstall', @source]
            success:
                state:'down'
                message: 'Service uninstalled'
        }, cb)

