async = require 'async'
service = require './service'

# This class implements npm packaged service
exports.Npm = class Npm extends service.Service

    startup: (params, cb) ->
        if typeof(params) == 'function'
            cb = params
            params = {}

        cb(null)

    shutdown: (params, cb) ->
        if typeof(params) == 'function'
            cb = params
            params = {}

        cb(null)


    install: (cb) ->
        @submit({
            entity: 'shell'
            package: "worker"
            message: "Install app"
            state:   "maintain"
            home: @home
            command:["./bin/node", './bin/npm', "-g", "--prefix", @home, 'install', @source]
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

