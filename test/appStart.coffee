main  = require '../main'
state = require '../state'
async = require 'async'
checker = require './checker'

exports.AppStartTest = class extends checker.Checker

    testAppStart: (cb)->
        async.waterfall [
             (cb)=>
                @expect 'maintain', 'Installing app: test', cb
             (cb)=>
                @expect 'up', 'App installed', cb
             (cb)=>
                @expect 'maintain', 'Starting daemon', cb
             (cb)=>
                @expect 'up', 'Online', cb
             (cb)=>
                @app.on 'state', 'onState', @id
                @app.startup {
                    source: 'test'
                    domain: 'localhost'
                    instance: @instance.id
                    account: @account.id
                }, cb
        ], cb

