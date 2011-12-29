_            = require 'underscore'
async        = require 'async'
account      = require './account'
serviceGroup = require './serviceGroup'
state        = require './state'

# Application object

exports.App = class App extends serviceGroup.ServiceGroup

    init: ->
        super()
        @name = "Master Node"
        # Instance ID service run on
        @instance = undefined
        # Application ID to run
        @app = undefined
        # User account to run
        @user = undefined
        # Domain
        @domain = 'cloudpub.us'

    startup: (params, cb)->
        if _.isString(params.instance)
            params.instance = [params.instance]


        super({}, cb)

installOnInstance = (app, instance, cb)->
    exports.log.info "Install #{app.id} on instance #{instance.id}"
    
    params = {
        id:'installer-' + app.id
        entity:'service'
        account:app.account
        app:app.id
        instance:instance.id
        address:instance.address
        user:instance.user
    }
    
    app.startService params, params, cb

createApp = (url, acc, cb)->
    state.loadOrCreate account.sha1( url ), 'app', (err, app)->
        return cb and cb(err) if err
        app.source = url
        app.account = acc
        app.save (err)->
            cb and cb(err, app) if err
            state.query 'instance', (err, instanses)->
                cb and cb(err, app) if err
                async.forEach instanses, async.apply(installOnInstance, app), (err)->
                    cb and cb(err, app)

# Init request handlers here
exports.init = (app, cb)->

    log = exports.log

    app.register 'app'

    app.post '/api/create/app', (req, resp)->
        url = req.param('url')
        if not url
            return resp.send 'Source is required', 500
        
        createApp url, req.session.uid, (err, app)->
            if err then return resp.send err, 500
            resp.send true

    cb and cb(null)
