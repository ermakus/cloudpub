async = require 'async'
service = require './service'

exports.Runtime = class Runtime extends service.Service
    
    init: ->
        super()
        @name = 'cloudpub-runtime'

    startup: (params..., cb) ->
        exports.log.info "#{@name} startup", params
        cb(null)

    shutdown: (params..., cb) ->
        exports.log.info "#{@name} shutdown", params
        cb(null)

    install: (cb) ->
        exports.log.info "#{@name} install"
        @submit(
            [
                {
                            entity: 'sync'
                            package: "worker"
                            message: "Sync service files"
                            state:   "maintain"
                            source: __dirname + "/bin"
                            target: "#{@home}/" # Slash important!
                            success:
                                state:'maintain'
                                message:'Done'
                },
                # Install runtime
                {
                            entity:  'shell'
                            package: 'worker'
                            message: "Compile node runtime"
                            state:   "maintain"
                            command:["install-node", @home]
                            success:
                                state:'up'
                                message: 'Runtime compiled'
                }
            ], cb)

    uninstall: (cb) ->
        exports.log.info "#{@name} uninstall"
        @submit({
            state: 'maintain'
            message: 'Uninstall runtime'
            entity:  'shell'
            package: 'worker'
            command:['rm','-rf', @home]
            success:
                state:'down'
                message: 'Runtime uninstalled'
            }, cb)

