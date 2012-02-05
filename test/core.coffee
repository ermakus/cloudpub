async    = require 'async'
assert   = require 'assert'
checker  = require './checker'
state    = require '../state'
settings = require '../settings'
sugar    = require '../sugar'

#### Core engine tests

exports.CoreTest = class extends checker.Checker

    #### Test object factory 
    test1_StateCreate: (cb)->
        testObj = {id:'TEST-UNSAVED',entity:'state'}
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
        state.loadOrCreate {id:"TEST-SERVICE",entity:"service",commitSuicide:true,doUninstall:true}, (err, service)=>
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
        group = { id:"TEST-GROUP", entity:"group", isInstalled:true, commitSuicide:true, user:settings.USER, address:'127.0.0.1' }
        state.loadOrCreate group, (err, group)=>
            return cb(err) if err
            group.on '*',       'onEvent',      @id
            group.on 'success', 'groupSuccess', @id
            tasks = [
                {id:"TEST-GROUP-WORKER-1",entity:"shell",command:['echo','One']}
                {id:"TEST-GROUP-WORKER-2",entity:"shell",command:['echo','Two']}
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
        queue = { id:"TEST-QUEUE", entity:"queue", isInstalled: true, doUnistall: true, commitSuicide:true }
        state.loadOrCreate queue, (err, queue)=>
            return cb(err) if err
            queue.on '*',       'onEvent',      @id
            queue.on 'success', 'queueSuccess', @id
            tasks = [
                {id:"TEST-QUEUE-WORKER-1",entity:"shell",command:['echo','Three']}
                {id:"TEST-QUEUE-WORKER-2",entity:"shell",command:['echo','Fourth']}
            ]
            queue.create tasks, (err)=>
                return cb(err) if err
                queue.start(cb)

    queueSuccess: (queue, cb)->
        assert.equal @expectedEvents.length, 0
        assert.equal queue.state, 'down'
        @emit 'success', @, cb

