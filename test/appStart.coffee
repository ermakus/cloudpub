path  = require 'path'
main  = require '../main'
state = require '../state'
async = require 'async'
checker = require './checker'

exports.AppStartTest = class extends checker.Checker

    testAppStart: (cb)->
        async.waterfall [
             (cb)=>
                @expect 'maintain', 'Install app', cb
             (cb)=>
                @expect 'up', 'App installed', cb
             (cb)=>
                @expect 'maintain', 'Starting daemon', cb
             (cb)=>
                @expect 'up', 'Online', cb
             (cb)=>
                @expect 'maintain', 'Attach to proxy', cb
             (cb)=>
                @expect 'up', 'Online public', cb
             (cb)=>
                @app.on 'state', 'onState', @id
                @app.startup {
                    source: 'cloudpub'
                    domain: 'cloudpub.us'
                    instance: @instance.id
                    account: @account.id
                }, cb
        ], cb

