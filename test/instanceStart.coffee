async    = require 'async'
http     = require 'http'
fs       = require 'fs'
settings = require '../settings'
sugar    = require '../sugar'
state    = require '../state'
test     = require './test'

exports.InstanceStartTest = class extends test.Test

    # Test instance startup
    test1InstanceStart: (cb)->
        async.waterfall [
             # Set expected states
             (cb)=>
                @expect([
                    ['maintain', 'Sync service files']
                    ['maintain', 'Done']
                    ['maintain', 'Compile node runtime']
                    ['maintain', 'Runtime compiled']
                    ['maintain', 'Compile proxy']
                    ['maintain', 'Proxy installed']
                    ['maintain', 'Configure proxy']
                    ['maintain', 'Proxy configured']
                    ['maintain', 'Start Proxy']
                    ['up',       'Online']
                ], cb)
            # Create instance
            (cb)=>
               state.loadOrCreate("test/INSTANCE", 'instance', cb)
            # Route state event to checker
            (instance, cb)=>
                @instance = instance.id
                sugar.route('state', @instance, 'onState', @id, cb)
            # Launch instance
            (cb)=>
                sugar.emit('launch', @instance, {
                    user: test.USER
                    address: test.ADDRESS
                    port: 8080
                    account: test.ACCOUNT
                }, cb)
        ], cb
