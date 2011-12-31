_            = require 'underscore'
async        = require 'async'
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

    # Create service JSON info from params and instance ID
    makeService: (instanceId, cb)->
        exports.log.info "Install #{@id} on instance #{instanceId}"
        state.load instanceId, (err, instance)=>
            cb and cb(err, {
                id:'node-' + @id + '-' + instance.id
                entity:'npm'
                package:'npm'
                account:@account
                app:@id
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
        @domain = params.source
        if not @domain
            return cb and cb(new Error("Domain not set"))
        @account = params.account
        if not @account
            return cb and cb(new Error("Account not set"))

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


# Init request handlers here
exports.init = (app, cb)->
    app.register 'app'
    cb and cb(null)
