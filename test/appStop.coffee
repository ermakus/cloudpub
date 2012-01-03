main  = require '../main'
state = require '../state'
async = require 'async'
checker = require './checker'

exports.AppStopTest = class extends checker.Checker

    testAppStop: (cb)->
        async.waterfall [
             (cb)=>
                @expect 'maintain', 'Detach from proxy', cb
             (cb)=>
                @expect 'maintain', 'Domain parked', cb
             (cb)=>
                @expect 'maintain', 'Stop daemon', cb
             (cb)=>
                @expect 'down', 'Terminated', cb
             (cb)=>
                @expect 'maintain', 'Uninstall app', cb
             (cb)=>
                @expect 'down', 'App uninstalled', cb
             (cb)=>
                @expect 'down', 'Deleted', cb
             (cb)=>
                @app.on 'state', 'onState', @id
                @app.shutdown {
                    data: 'delete'
                }, cb
        ], cb

