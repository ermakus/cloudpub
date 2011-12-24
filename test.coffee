# Runner for event-based tests
async  = require 'async'
_      = require 'underscore'
assert = require 'assert'
main   = require './main'
state  = require './state'

exports.setUp = (cb)->
    main.init (err, app)->
        if err then throw err
        cb()

exports["Start service"] = (unit)->

    state.create 'service-test', 'serviceTest', 'test/service', (err, test)->

        assert.ifError err
        assert.ok test

        setup = (test, cb)->
            if test.setUp then test.setUp(cb) else cb(null)

        tearDown = (test, cb)->
            if test.setUp then test.tearDown(cb) else cb(null)

        async.forEachSeries _.functions(test), ( (method, cb)->
                if method.indexOf('test') == 0
                    testMethod = test[method]
                    state.create 'service-test', 'serviceTest', 'test/service', (err, testObject)->
                        assert.ifError err
                        async.series [
                            (cb)-> setup( testObject, cb )
                            (cb)-> testMethod.call( testObject, cb )
                            (cb)-> tearDown( testObject, cb )
                        ], cb
                else
                    cb( null )
            ), (err) ->
                assert.ifError err
                unit.done()
