main  = require '../main'
state = require '../state'
async = require 'async'
checker = require './checker'

exports.InstanceTest = class extends checker.Checker

    # Test instance startup
    test1_InstanceStartup: (cb)->
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
                @instance.on 'state', 'onState', @id
                @instance.startup {
                    user: 'anton'
                    address: '127.0.0.1'
                    instance: @instance.id
                    account: @account.id
                }, cb
        ], cb

    # Test instance shutdown
    test2_InstanceShutdown: (cb)->
        async.waterfall [
             (cb)=>
                # 0. Online
                @expect 'up', 'Online', cb
             (cb)=>
                # 1. Stop daemon
                @expect 'maintain', 'Stop daemon', cb
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
                # 2. And uninstalled (todo: fix order)
                @expect 'down', 'Service uninstalled', cb
             (cb)=>
                # 3. Deleted 
                @expect 'down', 'Server deleted', cb
             (cb)=>
                @instance.on 'state', 'onState', @id
                @instance.shutdown {
                    mode: 'shutdown'
                }, cb
        ], cb

