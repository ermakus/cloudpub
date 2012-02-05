#### System daemom service base class
async   = require 'async'
_       = require 'underscore'
sugar   = require './sugar'
state   = require './state'
service = require './service'

#### Module class
# Represent npm module as service with task queue
exports.Module = class Module extends service.Service
    
    configure: (params..., cb)->
        sugar.vargs arguments
        if not @name then return cb(new Error("Module name not set"))
        super(params..., cb)
    
    # Execute jobs in queue
    execute: (tasks, next, cb)->
        sugar.vargs arguments
        exports.log.info "Execute job list", tasks
        state.loadOrCreate {entity:'queue', commitSuicide:true}, (err, queue)=>
            return cb(err) if err
            queue.user    = @user
            queue.address = @address
            queue.home    = @home
            queue.on 'success', next, @id
            queue.on 'failure', 'failure', @id
            queue.on 'state',   'setState', @id
            queue.create tasks, (err)->
                return cb(err) if err
                queue.start(cb)

# Create class method that run commands defined in module
# - *method* name of the method
# - *next* event name that should be fired on success
makeDelegate = (method, next)->
        # Define method (event handler)
        Module.prototype[method] = (service, cb)->
            sugar.vargs arguments
            exports.log.info "Module delegate", method
            # Load module by name
            try
                module = require "./" + @name
            catch err
                return cb(err)
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


