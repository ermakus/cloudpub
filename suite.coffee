# Runner for event-based tests
async   = require 'async'
_       = require 'underscore'
assert  = require 'assert'
main    = require './main'
state   = require './state'
queue   = require './queue'
checker = require './test/checker'
nconf   = require 'nconf'

exports.setUp = (cb)->
    main.init (err, app)->
        if err then throw err
        cb()

# Test suite
# Will run all testXXX methods from @testModule.@testEntity
# 
exports.Suite = class Suite extends queue.Queue

    init: ->
        super()
        @count = 0

    submitTest: (entity, package, cb)->
        # Submit method wrapper
        startMethod = (method, cb)=>
            if method.indexOf('test') == 0
                # Create new instance for each test method and submit to queue
                test = {
                    id:(package + '.' +  entity + '.' + method)
                    entity:entity
                    package:package
                    testMethod:method
                }
                @count += 1
                @submit test, cb
            else
                cb( null )
        
        # Create entity for introspection
        state.create null, entity, package, (err, test)=>
            return cb and cb(err) if err
            # Iterate over all methods
            async.forEachSeries( _.functions(test), startMethod, cb )

    submitTests: (params, cb)->
        async.forEachSeries params, ((meta, cb) => @submitTest(meta.entity, meta.package, cb)), cb

    success: (entity, cb)->
        setTimeout =>
            checker.dumpCache()
            exports.log.info "Test suite done. #{@count} test(s) executed."
            process.exit(0)
        , 100
        @clear cb

exports.init = (app, cb)->
    if nconf.get('test')

        list = (cb)->
            state.load 'test-suite', (err, item)->
                return cb and cb(err, item?.children)

        app.register 'suite', list

        async.waterfall [
            (cb) -> state.create('test-suite', 'suite', cb)
            (suite, cb)->
                suite.submitTests [
                        { entity:'stateTest',    package:'test/state'   }
                        { entity:'instanceTest', package:'test/instance' }
                ], (err)-> cb( err, suite )
            (suite, cb) -> suite.start(cb)
        ], cb
    else
        cb(null)