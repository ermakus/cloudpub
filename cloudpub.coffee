async = require 'async'
state = require './state'
service = require './service'

# This class implements the main cloudpub service

exports.Cloudpub = class Cloudpub extends service.Service

    # Configure service by params dictionary
    configure: (params..., cb)->
        @source = __dirname
        @name = "cloudpub"
        super params..., cb

    startup: (params..., cb) ->
        @submit({
            entity: 'shell'
            package: "worker"
            message: "Start Cloudpub"
            state:   "maintain"
            command:["kya", "params"]
            success:
                state:'up'
                message: 'Online'
        }, cb)

    shutdown: (params..., cb) ->
        @submit({
            entity: 'shell'
            package: "worker"
            message: "Stop Clodupub"
            state:   "maintain"
            command:["kya", "params"]
            success:
                state:'down'
                message: 'Terminated'
        }, cb)


    install: (cb) ->
        @submit({
            entity: 'shell'
            package: "worker"
            message: "Install Cloudpub"
            state:   "maintain"
            command:["npm", "-g", "--prefix", @home, 'install', @source]
            success:
                state:'maintain'
                message: 'Cloudpub Installed'
        }, cb)

    uninstall: (cb) ->
        @submit({
            state: 'maintain'
            message: "Uninstall Cloudpub"
            entity:  'shell'
            package: 'worker'
            command:["npm", "-g", "--prefix", @home, 'uninstall', @name]
            success:
                state:'maintain'
                message: 'Cloudpub Uninstalled'
        }, cb)

