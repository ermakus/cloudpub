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

# TODO: read from ~/.ssh/id_rsa.pub
PUBLIC_KEY = 'ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEArReBqZnuNxIKy/xHS2rIuCNOZ0nOmtJyLIr5lnJ26LPD3vRGzrpMNh4e7SKES70cSf8OW/d55G5Xi+VXExdL+ub6j/6++06wJYf63Ts4DFL4UGMlwob0VKS73KiVI1yk5FVKJ8BajaqMvWqSss59XD5bQoLQVdvtKjpaMPjPFMq+m170cRQF7sgf3iGfM9GoKVHU2+B3N6+DUIgX8DTdfikatY70cC8HwI0dl5M2bZbh+pNujij13oeM0zcZcjbrqn2VXt3vuEIhAd/UYp2mRPC+JI7lZAQmkoI+jHKHv2LOOaHC9yXFGpvG8p8yqu4Dbw7JoruDTlXsNoET6D2eow== cloudpub'


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

    # Default entity handler
    app.register = (entity)->
        
        # HTML page view
        app.get '/' + entity, (req, resp)->
            resp.render entity, {pubkey:PUBLIC_KEY}

        # API query handler
        app.get '/api/' + entity, account.ensure_login, (req, resp)->
            state.query entity, (err, data)->
                if err
                    resp.send err, 500
                else
                    resp.send data

        # API command handler
        app.post '/api/' + entity + '/:command', account.ensure_login,
            # Default command handler
            command.handler entity, (entity, id, cb ) ->
                # Create or load instance
                if id == 'new' then id = null
                state.load entity, id, cb

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
