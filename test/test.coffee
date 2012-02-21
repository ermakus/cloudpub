settings = require '../settings'
state    = require '../state'
cloudfu  = require '../cloudfu'
async    = require 'async'
assert   = require 'assert'

# Test account
exports.ACCOUNT = 'test/ACCOUNT'
exports.USER    = 'cloudpub'
exports.ADDRESS = '127.0.0.1'

hr = (symbol)->
    for i in [0..4]
        symbol = symbol+symbol
    symbol

# Base class for all tests
exports.Test = class Test extends cloudfu.Cloudfu

    init: ->
        super()
        @expectedEvents = []
        @expected = []
        @notify = false

    expect: (states, cb)->
        for state in states
            @expected.push { state:state[0], message:state[1] }
        @save cb

    # Check for expected event
    onEvent: (name, event..., cb)->
        if name == 'serviceState' then return cb(null)
        if name != @expectedEvents[0] and @expectedEvents[0] != '*'
            settings.log.error "Unexpected event: ", name
            settings.log.error "expect: ", @expectedEvents[0]
            console.trace()
            process.exit(1)
        settings.log.stdout hr('-')
        settings.log.stdout "Expected event: ", name, "(", @expectedEvents[0], ")"
        settings.log.stdout hr('-')
        @expectedEvents = @expectedEvents[1...]
        cb(null)

    # Check for expected state
    onState: (event, cb)->
        if @expected.length
            exp = @expected[0]
            if (exp.state != event.state) or ((exp.message != event.message) and (exp.message != undefined))
                if exp.state != '*'
                    # If failure, then die or notify suite
                    settings.log.error hr('=')
                    settings.log.error "Unexpected [" + event.state + "] " + event.message + " (" + event.id + ")"
                    settings.log.error "Expect: ", @expected[0]
                    settings.log.error hr('=')
                    console.trace()
                    err = new Error("Unexpected event:" + JSON.stringify(event))
                    assert.ifError err
                    return @emit 'failure', @, cb
        # If success, then print checkpoint
        settings.log.stdout hr('-')
        settings.log.stdout "Expected state [" + event.state + "] " + event.message + " (" + event.id + ")"
        settings.log.stdout hr('-')
        @expected = @expected[1...]
        @save (err)=>
            if not @expected.length
                @emit 'success', @, cb
            else
                cb and cb(err)


