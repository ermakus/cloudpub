spawn   = require('child_process').spawn
nconf   = require 'nconf'
_       = require 'underscore'
async   = require 'async'
state   = require './state'

#
# Work queue
#
exports.WorkQueue = class WorkQueue extends state.State

    init: ->
        super()
        # List of worker IDs
        @workers = []

    clear: (cb)->
        super (err)=>
            return cb and cb(err) if err
            @stopWork cb

    startWork: (cb) ->
        if @workers.length
            state.load @workers[0], (err, worker) ->
                return cb and cb(err) if err
                return cb and cb(err) if (worker.state == 'up')
                console.log "Worker #{worker.id} started", worker.id
                worker.setState 'up',(err)->
                    return cb and cb(err) if err
                    worker.start cb
        else
            cb and cb(null)

    stopWork: (cb)->
        kill = (workerId, cb)->
            state.load workerId, (err, worker)->
                return cb and cb(err) if err
                worker.stop cb

        # Clear all workers
        async.forEach @workers, kill, (err)=>
            return cb and cb(err) if err
            @workers = []
            @save cb

    # Worker error handler
    failure: (err, worker) ->
        console.log "Worker #{worker.id} failed", err
        # Reload worker state due to events issue
        state.load worker.id, (err, worker) =>
            if err then return
            @emit 'failure', err, worker
            # If state is down then process is killed
            if worker.state == 'down'
                return worker.clear()
            # else it failed
            @setState 'error', "Worker failed", (e)=>
                if worker.failure then worker.failure(err, worker)
                worker.setState 'error', err.message

    # Worker success handler
    success: (stdout, worker) ->
        console.log "Worker #{worker.id} succeeded"
        @emit 'success', stdout, worker
        @workers =  _.without @workers, worker.id
        @setState 'up', "Work finished", (err)=>
            if err then return
            if worker.success then worker.success(stdout, worker)
            worker.clear (err)=>
                if err then return
                @startWork()

    # Create new worker
    submit: ( type, params, cb ) ->
        console.log "Submit work #{type}:", params
        state.create null, type, 'worker', (err, worker) =>
            return cb and cb(err) if err
            worker.state = 'maintain'
            _.extend worker, params
            worker.on 'failure', (err, worker) => @failure(err, worker)
            worker.on 'success', (err, worker) => @success(err, worker)
            @workers.push worker.id
            @save (err) =>
                return cb and cb( err ) if err
                worker.save (err) =>
                    @startWork cb

SSH_PRIVATE_KEY='/home/anton/.ssh/id_rsa'
RUN_TIMEOUT=500
#
# Worker process
#
exports.Worker = class Worker extends state.State

    # Execute command on local system
    exec: (run, cb) ->
        console.log "Exec " + run.join " "
        stdout = ''
        stderr = ''
        ch = spawn run[0], run[1...]

        @pid = ch.pid

        ch.stdout.on 'data', (data) ->
            console.log "SHELL: ", data.toString()
            if stdout.length < 512
                stdout += data.toString()

        ch.stderr.on 'data', (data) ->
            stderr += data.toString()
            console.log "ERROR: ", data.toString()
        
        ch.on 'exit', (code) =>
            if code == 0
                @emit 'success', stdout, @
            else
                err = new Error( stderr[-64...] )
                @emit 'failure', err, @
        
        cb and cb( null )

    stop: (cb)->
        if @pid
            try
                process.kill @pid
            catch err
                console.log "Process with #{@pid} not exists", err
        @setState "down", "Killed", cb

# SSH global options
SSH = "ssh -i #{SSH_PRIVATE_KEY} -o StrictHostKeyChecking=no -o BatchMode=yes"

exports.Sync = class Sync extends Worker
    start: (cb)->
        if not @source  then return cb and cb(new Error("Copy source not set"))
        if not @target  then return cb and cb(new Error("Copy target not set"))
        if not @user    then return cb and cb(new Error("Remote user not set"))
        if not @address then return cb and cb(new Error("Remote address not set"))
        @exec [ __dirname + "/bin/sync", "-u", @user, "-a", @address, "-k", SSH_PRIVATE_KEY, @source, @target ], cb
    
# Execute command on remote system over ssh
exports.Shell = class Shell extends Worker
    start: ( cb ) ->
        if not @user    then return cb and cb(new Error("Remote user not set"))
        if not @address then return cb and cb(new Error("Remote address not set"))
        if not @command then return cb and cb(new Error("Shell command not set"))
        @exec SSH.split(' ').concat("-l", @user, @address).concat(@command), cb

# Preprocess config file by _.template
exports.Preproc = class Preproc extends Worker

    start: (cb) ->
        if not @source  then return cb and cb(new Error("Copy source not set"))
        if not @target  then return cb and cb(new Error("Copy target not set"))
        if not @user    then return cb and cb(new Error("Remote user not set"))
        if not @address then return cb and cb(new Error("Remote address not set"))
        console.log "Preproc #{@source} -> #{@target}: " + JSON.stringify @context
        fs.readFile @source, (err, cfg) =>
            if err
                return @emit 'failure', err, @
            cfg = _.template cfg.toString(), @context
            fs.writeFile @target, cfg, (err)=>
                if err
                    return @emit 'failure', err, @
                else
                    return @emit 'success', "Done", @
        @setState 'up', "Preprocessing", cb


exports.Proxy = class Proxy extends WorkQueue
    # Configure proxy
    start: (cb) ->
        async.series [
            # Generate SSH vhost
            async.apply( @submit, 'preproc',
                source:__dirname + '/nginx.vhost'
                target: @home + '/vhost'
                context: { service:@, params }
            ),
            async.apply( @submit, 'shell',
                command:["sudo", "ln", "-sf", "#{@home}/vhost", "/etc/nginx/sites-enabled/#{@id}.#{@user}.conf"]
            ),
            async.apply( @submit, 'shell',
                command:["sudo", "service", "nginx", "reload"]
            ) ], cb


exports.init = (app, cb)->
    app.register 'worker'
    cb and cb( null )
