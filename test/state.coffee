state = require '../state'
async = require 'async'
checker = require './checker'
assert = require 'assert'

exports.StateTest = class extends checker.Checker

    # Test event emitter
    test1_StateCreate: (cb)->
        testObj = {id:'test-queue',entity:'queue'}
        state.create testObj, (err, item)=>
            assert.ifError err
            assert.ok item
            assert.equal item.id, testObj.id
            assert.equal item.package, testObj.entity
            @emit 'success', @, cb

    ref_callback: (event, cb)->
        @called2 = true
        assert.equal event.target, @id
        cb( null )

    test2_EventEmitter: (cb)->
        @on 'callback', 'ref_callback', @id
        @emit 'callback', @, (err)=>
            assert.ifError err
            assert.ok @called2
            @emit 'success', @, cb

