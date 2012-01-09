main  = require '../main'
state = require '../state'
async = require 'async'
checker = require './checker'

exports.InstanceStopTest = class extends checker.Checker

    # Test instance shutdown
    testInstanceStop: (cb)->
        async.waterfall [
             (cb)=>
                @expect 'maintain', 'Stop Cloudpub', cb
             (cb)=>
                @expect 'maintain', 'Terminated', cb
              (cb)=>
                @expect 'maintain', 'Stop Proxy', cb
             (cb)=>
                @expect 'maintain', 'Offline', cb
             (cb)=>
                @expect 'maintain', 'Uninstall service', cb
             (cb)=>
                @expect 'maintain', 'Service uninstalled', cb
             (cb)=>
                @expect 'down', 'Deleted', cb
             (cb)=>
                @inst.on 'state', 'onState', @id
                @inst.stop {
                    data: 'delete'
                }, cb
        ], cb
