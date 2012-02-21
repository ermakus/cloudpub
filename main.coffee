express  = require 'express'
stylus   = require 'stylus'
assets   = require 'connect-assets'
async    = require 'async'
passport = require 'passport'
_        = require 'underscore'
command  = require './command'
session  = require './session'
settings = require './settings'
state    = require './state'

# Modules to preload when server mode
MODULES = [
    'sugar'
    'memory'
    'state'
    'rest'
    'session'
    'queue'
    'group'
    'account'
    'command'
    'service'
    'shell'
    'domain'
    'instance'
    'io'
    'suite'
    'registry'
    'cloudfu'
]

# Loaded modules
LOADED_MODULES = []

publicDir = __dirname + '/public'

process.chdir( __dirname )

SessionStore = session.SessionStore

# Create express server
createApp = ->
    app = express.createServer()
    app.set 'view engine', 'jade'
    app.use assets()
    app.use express.static(publicDir)
    app.use express.cookieParser()
    app.use express.bodyParser()
    # Initialize passport auth
    app.use(passport.initialize())
    app.use(passport.session())

    app.sessionStore = new SessionStore()

    # Session backend
    app.use express.session
        store: app.sessionStore
        secret:"(#^LHh(*YHI^YIJHDFSDLsdfKF"
        key:'cloudpub.sid'

    # Make 'session' available in views
    app.dynamicHelpers
        session: (req, res) -> return req.session

    app.register = command.register( app )

    app.get '/', (req, resp) -> resp.render 'main'
    app

# Load and initialize module
# app passed as first param and can be null
initModule = (app, module, cb = state.defaultCallback)->
    settings.log.debug "Init module: #{module}"
    mod = require "./#{module}"
    mod.id  = module
    mod.log = settings.log
    mod.defaultCallback = state.defaultCallback
    LOADED_MODULES.unshift mod
    if mod.init
        mod.init app, cb
    else
        cb(null)

# Stop module by calling 'stop' method
stopModule = (module, cb = state.defaultCallback)->
    settings.log.debug "Stop module", module.id
    LOADED_MODULES = _.without LOADED_MODULES, module
    if typeof(module.stop) == 'function'
        module.stop cb
    else
        cb( null )

# Init cloudpub engine
# initServer=true for socket.io/express handlers setup
# Call cb( error, server ) where server is express application
exports.init = (initServer,cb=state.defaultCallback) ->
    # First param optional
    if typeof(initServer) == 'function'
        cb = initServer
        initServer = true
    if initServer
        app = createApp()
        # Init all modules
        async.forEach MODULES, async.apply(initModule,app), (err)-> cb(err, app)
    else
        app = null
        # else do nothing
        cb(null, app)

# Stop engine
exports.stop = (cb=state.defaultCallback)->
    async.forEach LOADED_MODULES, stopModule, cb
