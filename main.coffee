express  = require 'express'
stylus   = require 'stylus'
assets   = require 'connect-assets'
async    = require 'async'
passport = require 'passport'

account  = require './account'
service  = require './service'
domain   = require './domain'
instance = require './instance'
io       = require './io'
state    = require './state'
command  = require './command'
worker   = require './worker'
ec2      = require './ec2'
queue    = require './queue'
appl     = require './app'
suite    = require './suite'

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
    
    async.series [
        async.apply(io.init, app),
        async.apply(state.init, app),
        async.apply(queue.init, app),
        async.apply(account.init, app),
        async.apply(appl.init, app),
        async.apply(service.init, app),
        async.apply(worker.init, app),
        async.apply(domain.init, app),
        async.apply(instance.init, app),
        async.apply(ec2.init, app),
        async.apply(suite.init, app),
    ], (err, res) -> cb(err, app)
