_        = require 'underscore'
async    = require 'async'
state    = require './state'
sugar    = require './sugar'
service  = require './service'
settings = require './settings'
account  = require './account'

# print helper
hr = (symbol)->
    for i in [0..6]
        symbol = symbol+symbol
    symbol + "\n"

# Cloudfu - command line service
exports.Cloudfu = class extends service.Service
    # Init stdout
    init: ->
        super()
        @stdout = exports.log.stdout
        @state   = 'up'
        @message = 'Executing'
        @method  = 'help'
        @commitSuicide = true

    # Start service
    # Command line tokens passed as arguments
    start: (args..., cb)->
        sugar.vargs( arguments )
        if args.length > 0
            @method = args[0]
            @args = args[1...]
        else
            @args = args
        if @[@method]
            super(cb)
        else
            cb( new Error("No kya handler: #{@method}") )

    # Call method on start
    startup: (args...,cb)->
        sugar.vargs( arguments )
        # Run @method on next tick
        process.nextTick =>
            @[@method] @args..., (err)=>
                if err
                    @emit 'failure', @, state.defaultCallback
                else
                    @emit 'success', @, state.defaultCallback
                @stop( state.defaultCallback )

        super(args...,cb)

    # Command handlers
    # No help yet
    help: (cb)->
        sugar.vargs( arguments )
        @stdout "Use the source, " + settings.USER
        @stdout "Look at #{__filename} for available commands"
        cb( new Error("Help not implemented" ) )

    # Query object storage
    query: (index, cb)->
        sugar.vargs( arguments )
        if _.isFunction(index)
            cb = index
            index = 'index/index'
        state.query index, (err, states)=>
            return cb(err) if err
            count = 0
            @stdout hr('-')
            @stdout "Index: #{index}\n"
            @stdout hr('-')
            for obj in states
                @stdout "#{obj.str()}\n"
                count += 1
            @stdout hr('-')
            @stdout "Total: #{count}\n"
            @stdout hr('-')
            cb(null)

    # Get object by ID
    get: (id, cb)->
        state.load id, 'state', (err, obj)=>
            return cb(err) if err
            count = 0
            @stdout hr('-')
            @stdout JSON.stringify obj
            @stdout hr('-')
            cb(null)

    # Run test suite
    test: (cb)->
        async.waterfall [
            (cb) -> state.create('test/SUITE', 'suite', cb)
            (suite, cb)->
                suite.createTests [
                        'core'
                        'instanceStart'
                        'appStart'
                        'appStop'
                        'instanceStop'
                ], (err)-> cb( err, suite )
            (suite, cb) -> suite.start(cb)
        ], (err)-> cb( err, true )

    # Just print params
    params: (params..., cb)->
        for key of params
            @stdout "#{key}=#{params[key]}"
        cb(null)

#
# Command line parser
# Entry point for bin/kya
#
exports.kya = (command, cb)->
    # Remove all options that handled by nconf
    args = _.filter( command, ((arg)->arg[0] != '-') )
    exports.log.debug "Command line: #{args.join(' ')}"

    # Load or create object
    state.loadOrCreate null, 'cloudfu', (err, state)->
        return cb( err ) if err
        # Take method name from args
        state.start args..., cb

# List all sessions for current user
listSessions = (entity, params, cb)->
    # Load account and instancies
    state.query 'cloudfu', cb

# Init HTTP request handlers
exports.init = (app, cb)->
    return cb(null) if not app
    app.register 'cloudfu', listSessions
    app.post '/kya', account.ensure_login, (req, resp)->
        req.params.account = req.session.uid
        exports.kya req.param('command').split(" "), (err)->
            if err
                resp.send err.message, 500
            else
                resp.send true
    cb(null)
