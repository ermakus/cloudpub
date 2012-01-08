async    = require 'async'
http     = require 'http'
fs       = require 'fs'
settings = require '../settings'
main     = require '../main'
state    = require '../state'
checker  = require './checker'

exports.InstanceStartTest = class extends checker.Checker

    # Test instance startup
    test1InstanceStart: (cb)->
        async.waterfall [
             (cb)=>
                @expect 'maintain', 'Sync service files', cb
             (cb)=>
                @expect 'maintain', 'Done', cb
             (cb)=>
                @expect 'maintain', 'Compile node runtime', cb
             (cb)=>
                @expect 'maintain', 'Runtime compiled', cb
             (cb)=>
                @expect 'maintain', 'Compile proxy', cb
             (cb)=>
                @expect 'maintain', 'Proxy installed', cb
             (cb)=>
                @expect 'maintain', 'Configure proxy', cb
             (cb)=>
                @expect 'maintain', 'Proxy configured', cb
             (cb)=>
                @expect 'maintain', 'Start Proxy', cb
             (cb)=>
                @expect 'maintain', 'Online', cb
             (cb)=>
                @expect 'maintain', 'Install Cloudpub', cb
             (cb)=>
                @expect 'maintain', 'Cloudpub Installed', cb
             (cb)=>
                @expect 'maintain', 'Start Cloudpub', cb
             (cb)=>
                @expect 'up', 'Online', cb
             (cb)=>
                @inst.on 'state', 'onState', @id
                @inst.launch {
                    id: settings.ID
                    user: settings.USER
                    address: '127.0.0.1'
                    port: '8080'
                    account: @acc.id
                }, cb
        ], cb
