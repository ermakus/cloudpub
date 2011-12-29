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

        params.services = [{entity:'cloudpub'}]
        super(params. cb)

create_app = (url, acc, cb)->
    state.loadOrCreate account.sha1( url ), 'app', (err, app)->
        return cb and cb(err) if err
        app.source = url
        app.account = acc
        app.save (err)->
            cb and cb(err, app)

# Init request handlers here
exports.init = (app, cb)->

    log = exports.log

    app.register 'app'

    app.post '/api/create/app', (req, resp)->
        url = req.param('url')
        if not url
            return resp.send 'Source is required', 500
        
        create_app url, req.session.uid, (err, app)->
            if err then return resp.send err, 500
            resp.send true

    state.load 'app-cloudpub', (err)->
        if not err then return cb and cb(null)
        state.create 'app-cloudpub', 'app', (err, item) ->
            return cb and cb(err) if err
            app.id = 'cloudpub'
            app.title = 'Cloudpub Node'
            item.save cb
