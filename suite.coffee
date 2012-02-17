# Runner for event-based tests
async   = require 'async'
_       = require 'underscore'
assert  = require 'assert'
main    = require './main'
state   = require './state'
queue   = require './queue'
checker = require './test/checker'
nconf   = require 'nconf'

# Test suite
# Will run all testXXX methods from @testModule.@testEntity
exports.Suite = class Suite extends queue.Queue

    init: ->
        super()
        @count = 0

    createTest: (name, cb)->
        entity = name + 'Test'
        package = 'test/' + name
        # Submit method wrapper
        startMethod = (method, cb)=>
            if method.indexOf('test') == 0
                # Create new instance for each test method and submit to queue
                test = {
                    id:( "test/" + name + "/" + method)
                    entity
                    package
                    testMethod:method
                }
                @count += 1
                @create test, cb
            else
                cb( null )

        # Create entity for introspection
        state.create null, entity, package, (err, test)=>
            return cb and cb(err) if err
            # Iterate over all methods
            async.forEachSeries( _.functions(test), startMethod, cb )

    createTests: (params, cb)->
        async.forEachSeries params, ((name, cb) => @createTest(name, cb)), cb

    success: (entity, cb)->
        setTimeout =>
            exports.log.info "Test suite done. #{@count} test(s) executed."
        , 500 # Give a time to execute callbacks
        @clear cb


