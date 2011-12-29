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

    # Create service JSON info from params and instance ID
    makeService: (params, instanceId, cb)->
        exports.log.info "Install #{@id} on instance #{instanceId}"
        state.load instanceId, (err, instance)=>
            cb and cb(err, {
                id:'node-' + @id + '-' + instance.id
                entity:'npm'
                package:'npm'
                account:params.account
                app:@id
                instance:instance.id
                address:instance.address
                user:instance.user
            })

    startup: (params, cb)->
        # Take parent prototype
        startup = serviceGroup.ServiceGroup.prototype.startup

        # One checkbox passed as string, so make it array
        if _.isString(params.instance)
            params.instance = [params.instance]

        # Create service for each instance
        async.map params.instance, ((id, cb)=>@makeService(params, id, cb)), (err, services)=>
            return cb and cb(err) if err
            params.services = services
            delete params['instance']
            # Call parent inside anonymous function. Sooo suxx
            startup.call @, params, cb

# Init request handlers here
exports.init = (app, cb)->
    app.register 'app'
    cb and cb(null)
