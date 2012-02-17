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
                    ['maintain', 'Online']
                    ['maintain', 'Install Cloudpub']
                    ['maintain', 'Cloudpub Installed']
                    ['maintain', 'Start Cloudpub']
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
                    user: settings.USER
                    address: '127.0.0.1'
                    port: 8080
                    account: @account
                }, cb)
        ], cb
