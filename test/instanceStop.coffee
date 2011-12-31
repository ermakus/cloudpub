main  = require '../main'
state = require '../state'
async = require 'async'
checker = require './checker'

exports.InstanceStopTest = class extends checker.Checker

    # Test instance shutdown
    testInstanceStop: (cb)->
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
                # 2. And uninstalled (todo: fix order)
                @expect 'down', 'Service uninstalled', cb
             (cb)=>
                # 3. Deleted 
                @expect 'down', 'Deleted', cb
             (cb)=>
                @instance.on 'state', 'onState', @id
                @instance.shutdown {
                    data: 'delete'
                }, cb
        ], cb
