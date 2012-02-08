async        = require 'async'
_            = require 'underscore'
account      = require './account'
group        = require './group'
state        = require './state'
settings     = require './settings'
sugar        = require './sugar'

#
# Instance is remote host that run bunch of services
#
exports.Instance = class Instance extends group.Group

    init: ->
        super()
        # Server address
        @address = undefined
        # SSH user
        @user = undefined
        # Owner account
        @account = undefined
        # Port to listen
        @port = 8080
        # Home dir
        @home = settings.HOME + '/cloudpub'

    # Launch instance and start some core services
    # This method called from WEB
    launch: (event, cb) ->
        exports.log.info "Start instance", @id

        # Init some params
        @account = event.account or @account
        @address = event.address or @address
        @user    = event.user    or @user
        @port    = parseInt(event.port or @port)
        @domain  = @domain or 'localhost'

        if not (@address and @user)
            return cb( new Error('Invalid address or user') )

        # Init home dir
        @home = (if @user == 'root' then '/root' else '/home/' + @user ) + '/cloudpub'

        # Define IDs
        @RUNTIME  = @id + "-runtime"
        @PROXY    = @id + "-proxy"

        # Declare services
        services = [
            { id:@RUNTIME,  entity:'module', name:'runtime',  port:0 }
            { id:@PROXY,    entity:'module', name:'proxy',    domain:@domain, default:true, port:@port }
        ]

        async.waterfall [
                # Create services
                (cb)=>
                    @create(services, cb)
                # Route events
                (cb)=> sugar.route( 'started', @RUNTIME,  'start',   @PROXY,    cb )
                (cb)=> sugar.route( 'started', @PROXY,    'started', @id,      cb )
                (cb)=> sugar.route( 'success', @PROXY,    'stop',    @RUNTIME,  cb )
                (cb)=> sugar.route( 'failure', @PROXY,    'stopped', @id,      cb )
                (cb)=> sugar.route( 'success', @RUNTIME,  'stopped', @id,      cb )
                (cb)=> sugar.route( 'failure', @RUNTIME,  'stopped', @id,      cb )
                 # Link instance with account
                (cb)=>
                    sugar.relate 'children', @account, @id, cb
                # Route events to account
                (cb)=>
                    sugar.route 'state', @id, 'serviceState', @account, cb
                # Start services
                (cb)=>
                    @start(cb)
            ], (err)->cb(err)

    # Startup event handler
    startup: (me, cb)->
        # Start main service
        # other services will start by events routing defined above
        sugar.emit( 'start', @RUNTIME, cb)

    # Stop instance (called from WEB)
    stop: (params, cb)->
        @doUninstall = @commitSuicide = (params.data == 'delete')
        super(params, cb)

    # Shutdown event handler
    shutdown: (me, cb)->
        async.series [
            # Pass uninstall flag to each children
            (cb)=> @each('set', {doUninstall:@doUninstall}, cb)
            # Stop master service
            (cb)=> @each('stop', cb)
        ], cb

    clear: (cb)->
        # Detach from account
        sugar.unrelate 'children', @account, @id, (err)=>
            group.Group.prototype.clear.call @, cb


# List instancies for account
listInstances = (entity, params, cb)->
    # Load account and instancies
    state.load params.account, (err, account)->
        # Load each instance
        async.map account.children, state.loadWithChildren, cb

# Init HTTP request handlers
exports.init = (app, cb)->
    return cb(null) if not app
    # Register CRUD handler
    app.register 'instance', listInstances
    cb(null)
