async = require 'async'
service = require './service'

# NPM package manager service
exports.Npm = class Npm extends service.Service

    configure: (params, cb)->
        @source = params.source or @source
        if not @source return cb and cb(new Error('Source not set'))
        super params, cb

    startup: (cb) ->
        @submit({
            entity:  "shell"
            package: "worker"
            message: "Starting daemon"
            state:   "maintain"
            command: ["#{@home}/cloudpub/bin/daemon",
                      "-b", "#{@home}/cloudpub",
                      "start", @id, "#{@home}/runtime/bin/node"]
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
            home:    "#{@home}/cloudpub"
            command:["#{@home}/cloudpub/bin/daemon", "stop", @id]
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
            target: "#{@home}/"
            command:['npm','install', @source]
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
            command:['npm','uninstall', @source]
            success:
                state:'down'
                message: 'Service uninstalled'
        }, cb)

