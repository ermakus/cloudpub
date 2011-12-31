express  = require 'express'
stylus   = require 'stylus'
assets   = require 'connect-assets'
async    = require 'async'
passport = require 'passport'
io       = require './io'
command  = require './command'

MODULES = [ 'state', 'queue', 'group', 'account', 'command', 'worker', 'service',
            'serviceGroup', 'domain', 'instance', 'ec2', 'app', 'suite', 'npm', 'registry' ]

publicDir = __dirname + '/public'

MemoryStore = express.session.MemoryStore


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

    app.sessionStore = new MemoryStore()

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


exports.init = (cb) ->
    
    app = createApp()

    load_module = (module, cb)->
        io.log.info "Init module: #{module}"
        mod = require "./#{module}"
        mod.log = io.log
        if mod.init
            mod.init app, cb
        else
            cb and cb(null)
        
    async.series [
        (cb)-> io.init(app, cb)
        (cb)-> async.forEachSeries MODULES, load_module, cb
    ], (err)-> cb and cb(err, app)
