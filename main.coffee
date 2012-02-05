express  = require 'express'
stylus   = require 'stylus'
assets   = require 'connect-assets'
async    = require 'async'
passport = require 'passport'
_        = require 'underscore'
command  = require './command'
session  = require './session'
settings = require './settings'

# Modules to load
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

SessionStore = session.SessionStore

# Init default logger
exports.log = settings.log

# Default callback
exports.defaultCallback = defaultCallback = (err)->
    if err
        exports.log.error "Default callback error", err.message or err, (new Error().stack).split("\n")[2]

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
initModule = (app, module, cb = defaultCallback)->
    exports.log.debug "Init module: #{module}"
    mod = require "./#{module}"
    mod.id  = module
    mod.log = exports.log
    mod.defaultCallback = defaultCallback
    LOADED_MODULES.unshift mod
    if mod.init
        mod.init app, cb
    else
        cb(null)

# Stop module by calling 'stop' method
stopModule = (module, cb = defaultCallback)->
    exports.log.debug "Stop module", module.id
    LOADED_MODULES = _.without LOADED_MODULES, module
    if typeof(module.stop) == 'function'
        module.stop cb
    else
        cb( null )

# Init cloudpub engine
# initServer=true for socket.io/express handlers setup
# return callback( error, server ) where server is express application
exports.init = (initServer,cb=defaultCallback) ->
    # First param optional
    if typeof(initServer) == 'function'
        cb = initServer
        initServer = true
    if initServer
        app = createApp()
    else
        app = null
    # Init all modules
    async.forEach MODULES, async.apply(initModule,app), (err)-> cb(err, app)

# Stop engine
exports.stop = (cb=defaultCallback)->
    async.forEach LOADED_MODULES, stopModule, cb
