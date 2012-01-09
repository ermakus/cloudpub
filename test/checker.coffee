settings = require '../settings'
state    = require '../state'
async    = require 'async'
assert   = require 'assert'

exports.log = state.log

hr = (symbol)->
    for i in [0..6]
        symbol = symbol+symbol
    symbol

exports.Checker = class Checker extends state.State

    init: ->
        super()
        @expected = []

    start: (cb) ->
        async.series [
                (cb)=>
                    @setState 'up', "Run #{@testMethod}", cb
                # Setup test object
                (cb)=>
                    if @setUp
                        @setUp(cb)
                    else
                        cb and cb(null)
                # Call test method
                (cb)=>
                    if @testMethod
                        @[@testMethod].call @, cb
                    else
                        cb and cb( new Error('Test method not defined') )
            ], cb

    stop: (cb)->
        @clear cb

    expect: (state, message, cb)->
        if typeof( message ) == 'function'
            cb = message
            message = undefined
        @expected.push {state,message}
        @save cb

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
    setUp: (callback)->

        async.waterfall [
            # Load test app
            (cb)->
                state.loadOrCreate('test-app', 'app', cb)
            # Save it
            (app, cb)=>
                @app = app
                app.events = {}
                app.save cb
            # Load test instance
            (cb)->
                state.loadOrCreate settings.ID, 'instance', cb
            # Save it
            (inst, cb)=>
                @inst = inst
                inst.address = '127.0.0.1'
                inst.user = settings.USERNAME
                inst.events = {}
                inst.save cb
            # Load test account 
            (cb)->
                state.loadOrCreate 'test-user', 'account', cb
            # Save it
            (acc, cb)=>
                @acc = acc
                acc.login = 'test'
                acc.events = {}
                acc.save cb

        ], callback

