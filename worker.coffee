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
    failure: (event, cb) ->
        console.log "Worker #{event.worker.id} failed", event.error
        # If state is down then process is killed
        if event.worker.state == 'down'
            @workers =  _.without @workers, worker.id
            @save (err)->
                return cb and cb(err) if err
                event.worker.clear cb
        else
            # else it failed
            @setState 'error', "Worker failed", (e)=>
                return cb and cb(e) if er
                event.worker.setState 'error', event.error.message, cb

    # Worker success handler
    success: (event, cb) ->
        console.log "Worker #{event.worker.id} succeeded"
        @workers =  _.without @workers, event.worker.id
        @setState 'up', "Work finished", (err)=>
            return cb and cb(err) if err
            event.worker.clear (err)=>
                return cb and cb(err) if err
                @startWork cb

    # Create new worker
    submit: ( type, params, cb ) ->
        console.log "Submit work #{type}:", params
        state.create null, type, 'worker', (err, worker) =>
            return cb and cb(err) if err
            worker.state = 'maintain'
            _.extend worker, params

            worker.on 'failure', 'failure', @id
            worker.on 'success', 'success', @id

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

        if @success then @on 'success', 'success', @id
        if @failure then @on 'failure', 'success', @id

        stdout = ''
        stderr = ''

        console.log "Exec " + (run.join " ")
        
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
                @emit 'success', { message:stdout, worker:@ }, (err)->
                    console.log "Success hanlder result", err
            else
                err = new Error( stderr )
                @emit 'failure', { error:err, worker:@ }, (err)->
                    console.log "Failure handler result", err
        
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
        cmd = SSH.split(' ').concat("-l", @user, @address)
        cmd = cmd.concat(@command)
        @exec cmd, cb

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
