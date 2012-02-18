settings = require '../settings'
state    = require '../state'
cloudfu  = require '../cloudfu'
async    = require 'async'
assert   = require 'assert'

# Test account
exports.ACCOUNT = 'test/ACCOUNT'

hr = (symbol)->
    for i in [0..6]
        symbol = symbol+symbol
    symbol

# Base class for all tests
exports.Test = class Test extends cloudfu.Cloudfu

    init: ->
        super()
        @expectedEvents = []
        @expected = []

    expect: (states, cb)->
        for state in states
            @expected.push { state:state[0], message:state[1] }
        @save cb

    # Check for expected event
    onEvent: (name, event..., cb)->
        if name == 'serviceState' then return cb(null)
        if name != @expectedEvents[0] and @expectedEvents[0] != '*'
            exports.log.error "Unexpected event: ", name
            exports.log.error "expect: ", @expectedEvents[0]
            console.trace()
            process.exit(1)
        exports.log.stdout hr('-')
        exports.log.stdout "Expected event: ", name
        exports.log.stdout hr('-')
        @expectedEvents = @expectedEvents[1...]
        cb(null)

    # Check for expected state
    onState: (event, cb)->
        if @expected.length
            exp = @expected[0]
            if (exp.state != event.state) or ((exp.message != event.message) and (exp.message != undefined))
                if exp.state != '*'
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
        exports.log.stdout hr('-')
        exports.log.stdout "Expected state [" + event.state + "] " + event.message + " (" + event.id + ")"
        exports.log.stdout hr('-')
        @expected = @expected[1...]
        @save (err)=>
            if not @expected.length
                @emit 'success', @, cb
            else
                cb and cb(err)


