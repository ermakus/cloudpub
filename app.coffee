express  = require 'express'
stylus   = require 'stylus'
assets   = require 'connect-assets'
nconf    = require 'nconf'

account  = require './account'
service  = require './service'
domain   = require './domain'
instance = require './instance'
io       = require './io'

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

    app.get '/', (req, resp) -> resp.render 'main'
    app

exports.init = (cb) ->
    nconf.file
        file: __dirname + '/settings.conf'

    app = createApp()
    account.init app, ->
        service.init app, ->
            domain.init app, ->
                instance.init app, ->
                    io.init app, ->
                        cb and cb( null, app )

