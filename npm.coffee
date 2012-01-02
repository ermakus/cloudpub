async = require 'async'
service = require './service'

# This class implements npm packaged service
exports.Npm = class Npm extends service.Service

    configure: (params, cb)->
        @source = params.source or @source
        if not @source then return cb and cb(new Error('Source not set'))
        super params, cb

    startup: (cb) ->
        @submit({
            entity:  "shell"
            package: "worker"
            message: "Starting daemon"
            state:   "maintain"
            home: @home
            command: ["./bin/npm", "-g", "--prefix", @home, "start", @source]
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
            home: @home
            command:["./bin/npm", "-g", "--prefix", @home, "stop", @source]
            success:
                state:   'down'
                message: 'Terminated'
        }, cb)

    install: (cb) ->
        @submit({
            entity: 'shell'
            package: "worker"
            message: "Installing app: #{@source}"
            state:   "maintain"
            home: @home
            command:['./bin/npm', "-g", "--prefix", @home, 'install', @source]
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
            command:['./bin/npm', "-g", "--prefix", @home, 'uninstall', @source]
            success:
                state:'down'
                message: 'Service uninstalled'
        }, cb)

