#### System daemom service base class
async   = require 'async'
_       = require 'underscore'
sugar   = require './sugar'
state   = require './state'
service = require './service'

#### Module class
# Represent module as service with task queue
exports.Module = class Module extends service.Service

    configure: (params..., cb)->
        sugar.vargs arguments
        if not @name then return cb(new Error("Module name not set"))
        @host = params.host or "127.0.0.1"
        super(params..., cb)

    # Execute jobs in queue
    execute: (tasks, next, cb)->
        sugar.vargs arguments
        exports.log.info "Execute job list", tasks
        state.loadOrCreate {entity:'queue', commitSuicide:true}, (err, queue)=>
            return cb(err) if err
            queue.user    = @user
            queue.address = @address
            queue.host    = @host
            queue.home    = @home
            queue.on 'success', next, @id
            queue.on 'failure', 'failure', @id
            queue.on 'state',   'setState', @id
            queue.create tasks, (err)->
                return cb(err) if err
                queue.start(cb)

    # Launch services
    # Called from WEB
    launch: (params, cb)->

        account = params.account
        source  = params.source
        name    = params.source
        domain  = params.domain
        port    = params.port

        if _.isEmpty( params.instance )
            cb( new Error("Servers not selected") )
        if _.isArray( params.instance )
            instancies = params.instance
        else
            instancies = [params.instance]

        # Helper function to launch service
        launchService = (instance, cb) ->
            exports.log.info "Launch service on", instance.id
            # Create and start service
            instance.create {
                id:(instance.id + '-' + name)
                entity:"module"
                autostart:true
                instance:instance.id
                proxy:instance.PROXY
                proxy_port:instance.port
                account
                name
                domain
                source
                port
            }, cb

        async.waterfall [
                # Load all instancies
                (cb)=> async.map(instancies, state.load, cb)
                # And launch service on each of them
                (inst, cb)=> async.forEach(inst, launchService, cb)
            ], (err)->cb(err)

    # Stop service (called from WEB)
    stop: (params..., cb)->
        if params.length
            @doUninstall = @commitSuicide = (params[0].data == 'delete')
        super(params..., cb)

    clear: (cb)->
        # Detach from instance
        sugar.unrelate 'children', @instance, @id, (err)=>
            service.Service.prototype.clear.call @, cb


# Create class method that run commands defined in module
# - *method* name of the method
# - *next* event name that should be fired on success
makeDelegate = (method, next)->
        # Define method (event handler)
        Module.prototype[method] = (service, cb)->
            sugar.vargs arguments
            exports.log.info "Module delegate", method
            # Try load module script by name
            try
                module = require "./pubs/" + @name
            catch err
                # if failed create default npm module
                module = require "./pubs/npm"
            # If there is no handler defined
            if method not of module
                # ..then just call Module default handler
                Module.__super__[method].call(@, service, cb)
            else
                # ..else we call function defined in module 
                # Handler can return job(s) to execute or null
                # In case of jobs module SHOULD NOT call callback.
                # If handler return null, the module should execute job by self and 
                # invoke callback after it done.
                tasks = module[method].call @, ((err) => if err then @emit('failure', err, cb) else @emit(next, @, cb ))
                if tasks
                    @execute( tasks, next, cb )

# Init delegates
makeDelegate( h[0], h[1] ) for h in [
            ['install',  'installed'],
            ['uninstall','uninstalled'],
            ['startup',  'started'],
            ['shutdown', 'stopped']
        ]


