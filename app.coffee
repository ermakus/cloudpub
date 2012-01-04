_            = require 'underscore'
async        = require 'async'
settings     = require './settings'
account      = require './account'
serviceGroup = require './serviceGroup'
state        = require './state'

# Application object

exports.App = class App extends serviceGroup.ServiceGroup

    init: ->
        super()
        # Instance ID service run on
        @instance = undefined
        # Domain
        @domain = undefined
        # Source
        @account = undefined
        # List of instancies app run
        @instancies = []
        # Port that application listen
        @port = "8081"
        # Interface
        @interface = "127.0.0.1"

    # Create service JSON info from params and instance ID
    makeService: (instanceId, cb)->
        exports.log.info "Install #{@id} on instance #{instanceId}"
        state.load instanceId, (err, instance)=>
            cb and cb(err, {
                entity:'npm'
                package:'npm'
                account:@account
                app:@id
                domain:@domain
                port:@port
                interface:@interface
                instance:instance.id
                address:instance.address
                user:instance.user
            })

    # Configure app from form data
    # params.account always passed if user authorized
    configure: (params, cb)->
        @source = params.source
        if not @source
            return cb and cb(new Error("Source not set"))
        @domain = params.domain
        if not @domain
            return cb and cb(new Error("Domain not set"))
        @account = params.account
        if not @account
            return cb and cb(new Error("Account not set"))
        @port = params.port or @port
        if not @port
            return cb and cb(new Error("Port not set"))


        params.instance ||= []
        # Single checkbox passed as string, so make it array
        if _.isString(params.instance)
            params.instance = [params.instance]
        @instancies = params.instance
        if _.isEmpty(@instancies)
            return cb and cb(new Error("Instancies not selected"))
        params.instance = undefined

        # Take parent prototype to call later
        configureSuper = serviceGroup.ServiceGroup.prototype.configure

        async.map @instancies, ((id,cb)=>@makeService(id,cb)), (err, services)=>
            return cb and cb(err) if err
            # Pass services as children to statup
            params.services = services
            # Call parent inside anonymous function. Sooo suxx
            configureSuper.call @, params, cb


# List apps for account
listApp = (entity, params, cb)->
    # Load account and services
    state.loadWithChildren params.account, (err, account)->
        # Collect unique apps from services
        apps = _.uniq( service.app for service in account._children)
        apps = _.compact apps
        # Load each and return
        async.map apps, state.loadWithChildren, cb

# Init request handlers here
exports.init = (app, cb)->
    return cb(null) if not app
    app.register 'app', listApp
    cb and cb(null)
