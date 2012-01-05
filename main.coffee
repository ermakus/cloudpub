express  = require 'express'
stylus   = require 'stylus'
assets   = require 'connect-assets'
async    = require 'async'
passport = require 'passport'
command  = require './command'
session  = require './session'
logger   = require './logger'

MODULES = [ 'state', 'memory', 'rest', 'session', 'queue', 'group', 'account', 'command', 'worker', 'service',
            'serviceGroup', 'domain', 'instance', 'io', 'app', 'suite', 'npm', 'registry', 'cloudfu' ]

publicDir = __dirname + '/public'

SessionStore = session.SessionStore

# Init default logger
exports.log = logger.create()

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


# Init cloudpub engine
# initServer=true for socket.io/express handlers setup
# return callback( error, server ) where server is express application
exports.init = (initServer,cb) ->
    # First param optional
    if typeof(initServer) == 'function'
        cb = initServer
        initServer = true

    if initServer
        app = createApp()
    else
        app = null

    # Load and initialize module
    # app passed as first param and can be null
    loadModule = (module, cb)->
        exports.log.debug "Init module: #{module}"
        mod = require "./#{module}"
        mod.log = exports.log
        if mod.init
            mod.init app, cb
        else
            cb(null)
    
    # Init all modules
    async.forEach MODULES, loadModule, (err)-> cb(err, app)
