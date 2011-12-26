state  = require '../state'
async  = require 'async'
assert = require 'assert'

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

    expect: (event, cb)->
        @expected.push event
        @save cb

    onState: (event, cb)->
        console.log "======================================================="
        if not @expected.length or @expected[0] != event.state
            console.log "Unexpected [" + event.state + "] " + event.message + " (" + event.id + ")"
            console.log "Expect: ", @expected[0]
            console.trace()
            err = new Error("Unexpected event:" + JSON.stringify(event))
            assert.ifError err
            @emit 'failure', @, cb
        else
            console.log "Expected [" + event.state + "] " + event.message + " (" + event.id + ")"
            console.log "======================================================="
            @expected = @expected[1...]
            @save (err)=>
                if not @expected.length
                    @emit 'success', @, cb
                else
                    cb and cb(err)
