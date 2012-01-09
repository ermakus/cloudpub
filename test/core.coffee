async    = require 'async'
assert   = require 'assert'
checker  = require './checker'
state    = require '../state'
settings = require '../settings'
sugar    = require '../sugar'

exports.CoreTest = class extends checker.Checker

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
        state.loadOrCreate queue.id, (err, queue)=>
            queue.clear( state.defaultCallback )

    test3_Queue: (cb)->
        state.loadOrCreate {id:"TEST-QUEUE",entity:"queue"}, (err, queue)=>
            return cb(err) if err
            queue.on 'success', 'queueSuccess', @id
            queue.user = settings.USER
            queue.address = '127.0.0.1'
            queue.submit {id:"TEST-QUEUE-WORKER",entity:"shell",package:"worker",command:['ps']}, (err)=>
                return cb(err) if err
                queue.start(cb)

    groupSuccess: (group)->
        @emit 'success', @, state.defaultCallback
        # Delete group 
        state.loadOrCreate "TEST-GROUP", (err, group)=>
            group.clear( state.defaultCallback )

    test4_Group: (cb)->
        state.loadOrCreate {id:"TEST-GROUP",entity:"group"}, (err, group)=>
            return cb(err) if err
            group.on 'success', 'groupSuccess', @id
            group.user = settings.USER
            group.address = '127.0.0.1'
            blueprint = {id:"TEST-GROUP-WORKER",entity:"shell",package:"worker",command:['ps']}
            group.create blueprint, (err)=>
                return cb(err) if err
                async.series [
                        (cb)=> sugar.route('success', blueprint.id, 'groupSuccess', @id, cb)
                        (cb)=> group.start(cb)
                    ], cb
