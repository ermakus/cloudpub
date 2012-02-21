async    = require 'async'
assert   = require 'assert'
test     = require './test'
state    = require '../state'
settings = require '../settings'
sugar    = require '../sugar'

#### Core engine tests

exports.CoreTest = class extends test.Test

    #### Test object factory 
    test0_StateCreate: (cb)->
        testObj = {id:'test/STATE',entity:'state'}
        state.loadOrCreate testObj, (err, item)=>
            return cb(err) if err
            assert.ok item
            assert.equal item.id, testObj.id
            assert.equal item.package, testObj.entity
            state.load testObj.id, (err, item2)=>
                return cb(err) if err
                assert.equal item, item2
                item2.clear (err)=>
                    return cb(err) if err
                    @emit 'success', @, cb

    #### Test account
    test1_Account: (cb)->
        async.waterfall [
            # Create test account 
            (cb)->
                state.loadOrCreate {id:test.ACCOUNT, email:'test@cloudpub.us'}, 'account', cb
            # Save and generate SSH keys
            (acc, cb)=>
                @account = acc.id
                acc.save(cb)
            # Route Account::key event to Test::success
            (cb)=>
                sugar.route('keyReady',@account, 'keyReady', @id, cb)
        ], (err)->cb(err)

    # Account key generated
    keyReady: (cb)->
        async.waterfall [
            # Load account 
            (cb)->
                state.load test.ACCOUNT, cb
            # Set test SSH keys and save
            (acc, cb)=>
                acc.public_key = settings.HOME + '/.ssh/id_rsa.pub'
                acc.private_key = settings.HOME + '/.ssh/id_rsa'
                acc.save(cb)
            # Emit test success
            (cb)=>
                @emit('success', @, cb)
        ], (err)->cb(err)


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
        @expectedEvents = ['starting','startup','*','*','*','*']
        group = { id:"test/GROUP", entity:"group", isInstalled:true, commitSuicide:true, account:test.ACCOUNT }
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
        assert.ok @expectedEvents.length < 2
        assert.equal group.state, 'down'
        @emit 'success', @, cb

    ##### Test services queue
    test5_Queue: (cb)->
        # TODO: Fix events
        @expectedEvents = ['starting','startup','*','*','*','success']
        queue = { id:"test/QUEUE", entity:"queue", isInstalled: true, doUnistall: true, commitSuicide:true, account:test.ACCOUNT }
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

