# Runner for event-based tests
async  = require 'async'
_      = require 'underscore'
assert = require 'assert'
main   = require './main'
state  = require './state'
queue  = require './queue'

exports.setUp = (cb)->
    main.init (err, app)->
        if err then throw err
        cb()

# Test suite
# Will run all testXXX methods from @testModule.@testEntity
# 
exports.Suite = class Suite extends queue.Queue

    submitTest: (test, cb)->

        test.on 'success', 'success', @id
        test.on 'failure', 'failure', @id

        async.series [
            (cb) => test.save(cb),
            (cb) => @add( test.id, cb),
        ], cb


    submitEntity: (entity, module, cb)->
        # Submit method wrapper
        startMethod = (method, cb)=>
            if method.indexOf('test') == 0
                # Create new instance for each test method and submit to queue
                state.create module + '.' +  entity + '.' + method, entity, module, (err, testObject) =>
                        return cb and cb(err) if err
                        testObject.testMethod = method
                        @submitTest testObject, cb
            else
                cb( null )
        
        # Creta entity for introspection
        state.create null, entity, module, (err, test)=>
            return cb and cb(err) if err
            # Iterate over all methods
            async.forEachSeries( _.functions(test), startMethod, cb )

    submit: (params, cb)->
        async.series [
            (cb) =>
                async.forEach params, ((meta, cb) => @submitEntity(meta.entity, meta.module, cb)), cb
            (cb) =>
                @start( cb )
            ], cb

exports.init = (app, cb)->
    if '--test' in process.argv

        list = (cb)->
            state.load 'test-suite', (err, item)->
                return cb and cb(err, item?.children)

        app.register 'suite', list

        async.waterfall [
            (cb) -> state.loadOrCreate('test-suite', 'suite', cb)
            (suite, cb)->
                suite.submit [entity:'serviceTest',module:'test/service'], cb
        ], cb
    else
        cb(null)
