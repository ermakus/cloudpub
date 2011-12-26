state = require '../state'
async = require 'async'
checker = require './checker'
assert = require 'assert'

exports.StateTest = class extends checker.Checker

    # Test event emitter
    test1_StateCreate: (cb)->
        testObj = {id:'ID',entity:'queue'}
        state.create testObj, (err, item)=>
            assert.ifError err
            assert.ok item
            assert.equal item.id, testObj.id
            assert.equal item.package, testObj.entity
            @emit 'success', @, cb

    callback: (event, cb)->
        @called = true
        assert.equal event, @
        cb( null )

    test2_EventEmitter: (cb)->
        @on 'callback', 'callback', @id
        @emit 'callback', @, (err)=>
            assert.ifError err
            assert.ok @called
            @emit 'success', @, cb

