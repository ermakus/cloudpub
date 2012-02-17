settings = require '../settings'
state    = require '../state'
service  = require '../service'
async    = require 'async'
assert   = require 'assert'

exports.log = state.log

hr = (symbol)->
    for i in [0..6]
        symbol = symbol+symbol
    symbol

exports.Test = class Test extends service.Service

    init: ->
        super()
        @expectedEvents = []
        @expected = []

    start: (params..., cb) ->
        async.series [
                (cb)=>
                    @setState 'up', "Run #{@testMethod}", cb
                # Setup test object
                (cb)=>
                    if @setUp
                        @setUp(cb)
                    else
                        cb(null)
                # Call test method
                (cb)=>
                    if @testMethod
                        @[@testMethod].call(@, cb)
                    else
                        cb( new Error('Test method not defined') )
            ], (err)->cb(err)


    expect: (states, cb)->
        for state in states
            @expected.push { state:state[0], message:state[1] }
        @save cb


    onEvent: (name, event..., cb)->
        if name == 'serviceState' then return cb(null)
        if name != @expectedEvents[0]
            exports.log.error "Unexpected event: ", name
            exports.log.error "expect: ", @expectedEvents[0]
            console.trace()
            process.exit(1)
        exports.log.info hr('-')
        exports.log.error "Expected event: ", name, event
        exports.log.info hr('-')
        @expectedEvents = @expectedEvents[1...]
        cb(null)

    # Check state event by @expected queue
    onState: (event, cb)->
        if @expected.length
            exp = @expected[0]
            if (exp.state != event.state) or ((exp.message != event.message) and (exp.message != undefined))
                # If failure, then die or notify suite
                exports.log.error hr('=')
                exports.log.error "Unexpected [" + event.state + "] " + event.message + " (" + event.id + ")"
                exports.log.error "Expect: ", @expected[0]
                exports.log.error hr('=')
                console.trace()
                err = new Error("Unexpected event:" + JSON.stringify(event))
                assert.ifError err
                return @emit 'failure', @, cb
        # If success, then print checkpoint
        exports.log.info hr('-')
        exports.log.info "Expected [" + event.state + "] " + event.message + " (" + event.id + ")"
        exports.log.info hr('-')
        @expected = @expected[1...]
        @save (err)=>
            if not @expected.length
                @emit 'success', @, cb
            else
                cb and cb(err)

    # Setup test environment
    setUp: (cb)->

        async.waterfall [
            # Create test account 
            (cb)->
                state.loadOrCreate 'test/ACCOUNT', 'account', cb
            # Save and generate SSH keys
            (acc, cb)=>
                @account = acc.id
                acc.email = 'test@user'
                acc.events = {}
                acc.generate(cb)
        ], (err)->cb(err)

