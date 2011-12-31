async = require 'async'
fs    = require 'fs'
main  = require '../main'
state = require '../state'
checker = require './checker'

exports.InstanceStartTest = class extends checker.Checker

    # Test instance startup
    testInstanceStart: (cb)->
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

