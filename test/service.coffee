main  = require '../main'
state = require '../state'
async = require 'async'
checker = require './checker'

exports.ServiceTest = class extends checker.Checker

    # Setup test environment
    setUp: (callback)->

        async.waterfall [
            # Create test app
            (cb)->
                state.create('test-app', 'app', cb)
            # Save it
            (app, cb)=>
                @application = app
                app.events = {}
                app.save cb
            # Create test instance
            (cb)->
                state.create 'test-instance', 'instance', cb
            # Save it
            (inst, cb)=>
                inst.address = '127.0.0.1'
                inst.user = 'anton'
                @instance = inst
                inst.save cb

        ], callback

    # Clear test objects
    tearDown: (callback)->
        async.series [
            (cb)=> @application.clear(cb),
            (cb)=> @instance.clear(cb),
        ], callback

    # Test event emitter
    test1_TestChecker: (cb)->
        async.waterfall [
            (cb)=>
                @expect('test', cb)
            (cb)=>
                @application.on('state', 'onState', @id)
                @application.emit('state', {'state':'test'}, cb)
        ], cb

    # Test app startup
    test2_Startup: (cb)->
        async.waterfall [
             (cb)=>
                # 1. Sync files...
                @expect 'maintain', 'Sync service files', cb
             (cb)=>
                # 2. Sync done
                @expect 'maintain', 'Service installed', cb
             (cb)=>
                # 3. Compiling
                @expect 'maintain', 'Install node.js runtime', cb
             (cb)=>
                # 4. Compiling done
                @expect 'maintain', 'Runtime compiled', cb
             (cb)=>
                # 5. Starting
                @expect 'maintain', 'Starting daemon', cb
             (cb)=>
                # 6. Complete
                @expect 'up', 'Online', cb
             (cb)=>
                @application.on 'state', 'onState', @id
                @application.startup {
                    domain: 'localhost'
                    instance: @instance.id
                }, cb
        ], cb    # Test app startup

    test3_Shutdown: (cb)->
        async.waterfall [
             (cb)=>
                # 1. Stop daemon
                @expect 'maintain', 'Stop daemon', cb
             (cb)=>
                # 1. Daemon stopped
                @expect 'down', 'Terminated', cb
             (cb)=>
                # 3. Uninstalling service
                @expect 'maintain', 'Uninstall service', cb
             (cb)=>
                # 3. Uninstalled
                @expect 'down', 'Service uninstalled', cb
             (cb)=>
                @application.on 'state', 'onState', @id
                @application.shutdown {
                    data: 'delete'
                    instance: @instance.id
                }, cb
        ], cb
