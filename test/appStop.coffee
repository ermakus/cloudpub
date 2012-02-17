async = require 'async'
main  = require '../main'
state = require '../state'
test  = require './test'

exports.AppStopTest = class extends test.Test

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

