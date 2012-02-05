async    = require 'async'
http     = require 'http'
fs       = require 'fs'
settings = require '../settings'
sugar    = require '../sugar'
state    = require '../state'
checker  = require './checker'

exports.InstanceStartTest = class extends checker.Checker

    # Test instance startup
    test1InstanceStart: (cb)->
        async.waterfall [
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

            (cb)=>
                sugar.route('state', @inst, 'onState', @id, cb)

            (cb)=>
                sugar.emit('launch', @inst, {
                    id: settings.ID
                    user: settings.USER
                    address: '127.0.0.1'
                    port: '8080'
                    account: @acc
                }, cb)
        ], cb
