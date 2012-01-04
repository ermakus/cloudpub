settings = require '../settings'
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
                @expect 'maintain', 'Sync service files', cb
             (cb)=>
                @expect 'maintain', 'Service installed', cb
             (cb)=>
                @expect 'maintain', 'Compile node runtime', cb
             (cb)=>
                @expect 'maintain', 'Runtime compiled', cb
             (cb)=>
                @expect 'maintain', 'Configure proxy', cb
             (cb)=>
                @expect 'maintain', 'Proxy configured', cb
             (cb)=>
                @expect 'maintain', 'Start daemon', cb
             (cb)=>
                @expect 'up', 'Online', cb
             (cb)=>
                @instance.on 'state', 'onState', @id
                @instance.startup {
                    user: settings.USERNAME
                    address: '127.0.0.1'
                    port: '8080'
                    instance: @instance.id
                    account: @account.id
                }, cb
        ], cb

