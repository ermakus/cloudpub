sugar  = require '../sugar'
state  = require '../state'
async  = require 'async'
test   = require './test'

exports.InstanceStopTest = class extends test.Test

    # Test instance shutdown
    testInstanceStop: (cb)->
        async.series [
            (cb)=>
                @expect([
                    ['maintain', 'Stop Cloudpub']
                    ['maintain', 'Terminated']
                    ['maintain', 'Uninstall Cloudpub']
                    ['maintain', 'Cloudpub Uninstalled']
                    ['maintain', 'Stop Proxy']
                    ['maintain', 'Offline']
                    ['maintain', 'Uninstall proxy']
                    ['maintain', 'Proxy uninstalled']
                    ['maintain', 'Uninstall runtime']
                    ['down',     'Runtime uninstalled']
                ], cb)
            (cb)=>
                sugar.route( 'state', @inst, 'onState', @id, cb)
            (cb)=>
                sugar.emit( 'stop', @inst, {data:'delete'}, cb )
        ], cb
