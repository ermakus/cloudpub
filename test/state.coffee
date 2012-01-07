checker  = require './checker'
state    = require '../state'
settings = require '../settings'
async    = require 'async'
assert   = require 'assert'

exports.StateTest = class extends checker.Checker

    # Test event emitter
    test1_StateCreate: (cb)->
        testObj = {id:'TEST-QUEUE',entity:'queue'}
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
            return cb(err) if err
            assert.ok @called2
            @emit 'success', @, cb

    queueSuccess: (queue)->
        @emit 'success', @, state.defaultCallback

    test3_Queue: (cb)->
        state.loadOrCreate {id:"TEST-QUEUE", "test-queue",entity:"queue"}, (err, queue)=>
            return cb(err) if err
            queue.on 'success', 'queueSuccess', @id
            queue.user = settings.USER
            queue.address = '127.0.0.1'
            queue.submit {id:"TEST-WORKER",entity:"shell",package:"worker",command:['ps']}, (err)=>
                return cb(err) if err
                queue.start(cb)
