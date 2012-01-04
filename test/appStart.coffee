path  = require 'path'
main  = require '../main'
state = require '../state'
async = require 'async'
checker = require './checker'
redis = require 'redis'

exports.AppStartTest = class extends checker.Checker

    test1AppStart: (cb)->
        async.waterfall [
             (cb)=>
                @expect 'maintain', 'Install app', cb
             (cb)=>
                @expect 'up', 'App installed', cb
             (cb)=>
                @expect 'maintain', 'Start app', cb
             (cb)=>
                @expect 'up', 'Online', cb
             (cb)=>
                @expect 'maintain', 'Attach to proxy', cb
             (cb)=>
                @expect 'up', 'Online public', cb
             (cb)=>
                @app.on 'state', 'onState', @id
                @app.startup {
                    name: 'cloudpub-redis'
                    source: '/home/anton/Projects/cloudpub-redis'
                    domain: 'redis.cloudpub.us'
                    port: '8081'
                    instance: @instance.id
                    account: @account.id
                }, cb
        ], cb

    test2AppValidate: (cb)->
        client = redis.createClient(@app.port)
        client.on 'connected', =>
            @emit 'success', @, cb
        client.on 'connection error', (err)=>
            @message = err
            @emit 'failure', @, cb
        cb( null )

