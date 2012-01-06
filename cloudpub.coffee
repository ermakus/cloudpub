async = require 'async'
state = require './state'
service = require './service'

# This class implements npm packaged service

exports.Cloudpub = class Cloudpub extends service.Service

    # Configure service by params dictionary
    configure: (params, cb)->
        @source = __dirname
        @name = "cloudpub"
        super params, cb

    startup: (params, cb) ->
        if typeof(params) == 'function'
            cb = params
            params = {}

        @submit({
            entity: 'shell'
            package: "worker"
            message: "Start app"
            state:   "maintain"
            command:["kya", "startup", @id]
            success:
                state:'up'
                message: 'Online'
        }, cb)

    shutdown: (params, cb) ->
        if typeof(params) == 'function'
            cb = params
            params = {}
        @submit({
            entity: 'shell'
            package: "worker"
            message: "Stop service"
            state:   "maintain"
            command:["kya", "shutdown", @id]
            success:
                state:'up'
                message: 'Terminated'
        }, cb)


    install: (cb) ->
        @submit({
            entity: 'shell'
            package: "worker"
            message: "Install app"
            state:   "maintain"
            command:["npm", "-g", "--prefix", @home, 'install', @source]
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
            command:["npm", "-g", "--prefix", @home, 'uninstall', @name]
            success:
                state:'down'
                message: 'App uninstalled'
        }, cb)

