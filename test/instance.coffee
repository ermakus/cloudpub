main  = require '../main'
state = require '../state'
async = require 'async'

application = null
instance    = null
listener    = null

# Setup test environment
exports.setUp = (callback)->

    async.waterfall [
        # Init app
        (cb)->
            main.init cb
        # Create test listener
        ,(server, cb)->
            state.create 'test-listener', 'checker', cb
        # Save it
        ,(lst, cb)->
            listener = lst
            listener.save cb
        # Create test app
        ,(cb)->
            state.create 'test-app', 'app', cb
        # Save it
        ,(app, cb)->
            application = app
            app.save cb
        # Create test instance
        ,(cb)->
            state.create 'test-instance', 'instance', cb
        # Save it
        ,(inst, cb)->
            instance = inst
            inst.address = '127.0.0.1'
            inst.user = 'anton'
            inst.save cb

    ], (err)->
        if err then throw err
        callback()

# Clear test objects
exports.tearDown = (callback)->
    async.series [
        listener.clear,
        application.clear,
        instance.clear
    ], callback

# Test event emitter
exports["Event emitter"] = (assert)->
    async.waterfall [
        (cb)->
            listener.expect 'test', cb
        ,(cb)->
            application.on 'state', 'onState', 'test-listener'
            application.emit 'state', {'state':'test'}, cb
    ], (err)->
        assert.ifError err
        assert.done()

# Test app startup
exports["Startup"] = (assert)->
    console.log "Check starting up"
    async.waterfall [
         (cb)->
            # 1. Installing
            listener.expect 'maintain', cb
        ,(cb)->
            # 2. Compiling
            listener.expect 'maintain', cb
         ,(cb)->
            # 3. Launching
            listener.expect 'maintain', cb
         ,(cb)->
            # 4. Done
            listener.expect 'up', cb
        ,(cb)->
            application.on 'state', 'onState', 'test-listener'
            application.startup {
                domain: 'localhost'
                instance: instance.id
            }, cb
    ], (err)->
       assert.ifError err
       assert.done()

