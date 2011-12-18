spawn   = require('child_process').spawn
nconf   = require 'nconf'
_       = require 'underscore'
async   = require 'async'
uuid    = require './uuid'
state   = require './state'


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
                err = new Error( stdout )
                @emit 'failure', stderr, @
        
        cb and cb( null )


# SSH global options
SSH = "ssh -i #{SSH_PRIVATE_KEY} -o StrictHostKeyChecking=no -o BatchMode=yes"

exports.Copy = class Copy extends Worker
    start: (cb)->
        if not @source  then return cb and cb(new Error("Copy source not set"))
        if not @target  then return cb and cb(new Error("Copy target not set"))
        if not @user    then return cb and cb(new Error("Remote user not set"))
        if not @address then return cb and cb(new Error("Remote address not set"))
        @exec [ __dirname + "/bin/copy", "-u", @user, "-a", @address, "-k", SSH_PRIVATE_KEY, @source, @target ], cb
    
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

#
# Work queue
#
exports.WorkQueue = class WorkQueue extends state.State

    init: ->
        super()
        # List of worker IDs
        @workers = []

    startWork: (cb) ->
        if @workers.length
            state.load @workers[0], (err, worker) ->
                return cb and cb(err) if err
                console.log "Start worker", worker.id
                worker.setState 'up', 'Started', (err)->
                    return cb and cb(err) if err
                    worker.start cb
        else
            cb and cb(null)

    failure: (err, worker) ->
        console.log "Worker #{worker.id} failed", err
        @emit 'failure', err, worker
        @workers =  _.without @workers, worker.id
        @setState 'error', err, (e)=>
            if worker.failure then worker.failure(err, worker)
            worker.clear()

    success: (stdout, worker) ->
        console.log "Worker #{worker.id} succeeded"
        @emit 'success', stdout, worker
        @workers =  _.without @workers, worker.id
        @setState 'up', stdout, (err)=>
            if err then return
            if worker.success then worker.success(stdout, worker)
            worker.clear (err)=>
                if err then return
                @startWork()

    # Create new worker
    submit: ( type, params, cb ) ->
        id = uuid.v1()
        state.load id, type, 'worker', (err, worker) =>
            return cb and cb(err) if err
            worker.state = 'maintain'
            worker.message = 'Waiting...'
            _.extend worker, params
            worker.on 'state',   (state, msg)  => @setState(state, msg)
            worker.on 'failure', (err, worker) => @failure(err, worker)
            worker.on 'success', (err, worker) => @success(err, worker)
            @workers.push worker.id
            @save (err) =>
                return cb and cb( err ) if err
                worker.save (err) =>
                    worker.start cb

exports.init = (app, cb)->
    app.register 'worker'
    cb and cb( null )
