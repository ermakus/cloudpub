main  = require '../main'
state = require '../state'
async = require 'async'
checker = require './checker'

exports.ServiceTest = class extends checker.Checker

    # Test event emitter
    test1_TestChecker: (cb)->
        async.waterfall [
            (cb)=>
                @expect('test', cb)
            (cb)=>
                @application.on('state', 'onState', @id)
                @application.emit('state', {'state':'test'}, cb)
        ], cb

    # Test app startup
    test2_AppStartup: (cb)->
        async.waterfall [
             (cb)=>
                # 1. Sync files...
                @expect 'maintain', 'Sync service files', cb
             (cb)=>
                # 2. Sync done
                @expect 'maintain', 'Service installed', cb
             (cb)=>
                # 3. Compiling
                @expect 'maintain', 'Install node.js runtime', cb
             (cb)=>
                # 4. Compiling done
                @expect 'maintain', 'Runtime compiled', cb
             (cb)=>
                # 5. Starting
                @expect 'maintain', 'Starting daemon', cb
             (cb)=>
                # 6. Complete
                @expect 'up', 'Online', cb
             (cb)=>
                @application.on 'state', 'onState', @id
                @application.startup {
                    domain: 'localhost'
                    instance: @instance.id
                    account: @account.id
                }, cb
        ], cb    # Test app startup

    test3_AppShutdown: (cb)->
        async.waterfall [
             (cb)=>
                # 1. Stop daemon
                @expect 'maintain', 'Stop daemon', cb
             (cb)=>
                # 1. Daemon stopped
                @expect 'down', 'Terminated', cb
             (cb)=>
                # 3. Uninstalling service
                @expect 'maintain', 'Uninstall service', cb
             (cb)=>
                # 3. Uninstalled
                @expect 'down', 'Service uninstalled', cb
             (cb)=>
                @application.on 'state', 'onState', @id
                @application.shutdown {
                    data: 'delete'
                    instance: @instance.id
                    account: @account.id
                }, cb
        ], cb
