async    = require 'async'
assert   = require 'assert'
test     = require './test'
state    = require '../state'
settings = require '../settings'
sugar    = require '../sugar'

#### Core engine tests

exports.CoreTest = class extends test.Test

    #### Test object factory 
    test1_StateCreate: (cb)->
        exports.log.debug("State created")
        testObj = {id:'test/UNSAVED',entity:'state'}
        state.create testObj, (err, item)=>
            return cb(err) if err
            assert.ok item
            assert.equal item.id, testObj.id
            assert.equal item.package, testObj.entity
            @emit 'success', @, cb

    #### Test event emitter
    test2_EventEmitter: (cb)->
        @on 'callback', 'ref_callback', @id
        @emit 'callback', "one","two", (err)=>
            return cb(err) if err
            return cb(new Error("Emit error")) unless @called
            @emit 'success', @, cb

    ref_callback: (one, two, cb)->
        @called = true
        assert.equal one, "one"
        assert.equal two, "two"
        cb( null )

    #### Test service lifecycle
    test3_Service: (cb)->
        @expectedEvents = ['starting','install','installed','startup','started']
        state.loadOrCreate {id:"test/SERVICE",entity:"service",commitSuicide:true,doUninstall:true}, (err, service)=>
            service.on '*',       'onEvent',  @id
            service.on 'started', 'serviceStarted', @id
            service.start(cb)

    serviceStarted: (service, cb)->
        assert.equal @expectedEvents.length, 0
        assert.equal service.state, 'up'
        @expectedEvents = ['shutdown', 'stopped', 'uninstall','uninstalled','success']
        service.on   'success', 'serviceStopped', @id
        service.stop(cb)

    serviceStopped: (service, cb)->
        assert.equal @expectedEvents.length, 0
        assert.equal service.state, 'down'
        @emit('success', @, cb)

    #### Test services group
    test4_Group: (cb)->
        @expectedEvents = ['starting','startup','state', 'state', 'stopped','success']
        group = { id:"test/GROUP", entity:"group", isInstalled:true, commitSuicide:true, account:@account }
        state.loadOrCreate group, (err, group)=>
            return cb(err) if err
            group.on '*',       'onEvent',      @id
            group.on 'success', 'groupSuccess', @id
            tasks = [
                {id:"test/group/WORKER-1",entity:"shell",command:['echo','One']}
                {id:"test/group/WORKER-2",entity:"shell",command:['echo','Two']}
            ]
            group.create tasks, (err)=>
                return cb(err) if err
                group.start(cb)

    groupSuccess: (group, cb)->
        assert.equal @expectedEvents.length, 0
        assert.equal group.state, 'down'
        @emit 'success', @, cb

    ##### Test services queue
    test5_Queue: (cb)->
        @expectedEvents = ['starting','startup','started','state','stopped','success']
        queue = { id:"test/QUEUE", entity:"queue", isInstalled: true, doUnistall: true, commitSuicide:true, account:@account }
        state.loadOrCreate queue, (err, queue)=>
            return cb(err) if err
            queue.on '*',       'onEvent',      @id
            queue.on 'success', 'queueSuccess', @id
            tasks = [
                {id:"test/queue/WORKER-1",entity:"shell",command:['echo','Three']}
                {id:"test/queue/WORKER-2",entity:"shell",command:['echo','Fourth']}
            ]
            queue.create tasks, (err)=>
                return cb(err) if err
                queue.start(cb)

    queueSuccess: (queue, cb)->
        assert.equal @expectedEvents.length, 0
        assert.equal queue.state, 'down'
        @emit 'success', @, cb

