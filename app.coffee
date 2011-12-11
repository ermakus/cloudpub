express  = require 'express'
stylus   = require 'stylus'
assets   = require 'connect-assets'

account  = require './account'
service  = require './service'
domain   = require './domain'

publicDir = __dirname + '/public'

createApp = ->
    app = express.createServer()
    app.set 'view engine', 'jade'
    app.use assets()
    app.use express.static(publicDir)
    app.use express.cookieParser()
    app.use express.bodyParser()

    # Session backend
    app.use express.session
        secret:"(#^LHh(*YHI^YIJHDFSDLsdfKF"

    # Make 'session' available in views
    app.dynamicHelpers
        session: (req, res) -> return req.session

    app.get '/', (req, resp) -> resp.render 'main'
    app

exports.init = (cb) ->
    app = createApp()
    account.init app, ->
        service.init app, ->
            domain.init app, ->
                cb and cb( null, app )
