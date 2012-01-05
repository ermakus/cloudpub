async = require 'async'
state = require './state'
service = require './service'

# This class implements npm packaged service

exports.Npm = class Npm extends service.Service

    # Configure service by params dictionary
    configure: (params, cb)->
        @source = params.source or @source
        if not @source then return cb and cb(new Error('Source not set'))
        @name = params.name or @name
        if not @name then return cb and cb(new Error('Unnamed module'))
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
            home: @home
            command:["./bin/node", './bin/kya', "params", @id]
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
            home: @home
            command:["./bin/node", './bin/kya', "shutdown", @id]
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
            command:["./bin/node", './bin/npm', "-g", "--prefix", @home, 'uninstall', @name]
            success:
                state:'down'
                message: 'App uninstalled'
        }, cb)

