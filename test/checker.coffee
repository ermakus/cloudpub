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

    expect: (state, message, cb)->
        if typeof( message ) == 'function'
            cb = message
            message = undefined
        @expected.push {state,message}
        @save cb

    onState: (event, cb)->
        console.log "======================================================="
        
        if @expected.length
            exp = @expected[0]
            if (exp.state != event.state) or ((exp.message != event.message) and (exp.message != undefined))
                console.log "Unexpected [" + event.state + "] " + event.message + " (" + event.id + ")"
                console.log "Expect: ", @expected[0]
                console.trace()
                err = new Error("Unexpected event:" + JSON.stringify(event))
                assert.ifError err
                return @emit 'failure', @, cb

        console.log "Expected [" + event.state + "] " + event.message + " (" + event.id + ")"
        console.log "======================================================="
        @expected = @expected[1...]
        @save (err)=>
            if not @expected.length
                @emit 'success', @, cb
            else
                cb and cb(err)
