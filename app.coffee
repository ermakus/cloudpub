express  = require 'express'
stylus   = require 'stylus'
assets   = require 'connect-assets'
nconf    = require 'nconf'
async    = require 'async'

account  = require './account'
service  = require './service'
domain   = require './domain'
instance = require './instance'
io       = require './io'
state    = require './state'
command  = require './command'
worker   = require './worker'

publicDir = __dirname + '/public'

MemoryStore = express.session.MemoryStore


createApp = ->
    app = express.createServer()
    app.set 'view engine', 'jade'
    app.use assets()
    app.use express.static(publicDir)
    app.use express.cookieParser()
    app.use express.bodyParser()
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
    nconf.file
        file: __dirname + '/settings.conf'

    app = createApp()
    
    async.parallel [
        async.apply(account.init, app),
        async.apply(service.init, app),
        async.apply(domain.init, app),
        async.apply(instance.init, app),
        async.apply(worker.init, app),
        async.apply(io.init, app),
    ], (err, res) -> cb(err, app)
