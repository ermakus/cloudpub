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
            stdout += data.toString()

        ch.stderr.on 'data', (data) ->
            stderr += data.toString()
            console.log "ERROR: ", data.toString()
        
        ch.on 'exit', (code) =>
            if code == 0
                @emit 'success', null, @
            else
                @emit 'failure', new Error( stderr ), @
        
        cb and cb( null )


exports.Scp = class Scp extends Worker
    start: (cb)->
        if not @source  then return cb and cb(new Error("Copy source not set"))
        if not @target  then return cb and cb(new Error("Copy target not set"))
        if not @user    then return cb and cb(new Error("Remote user not set"))
        if not @address then return cb and cb(new Error("Remote address not set"))
        cmd = ["scp", '-r', '-c', 'blowfish', '-C', '-i', SSH_PRIVATE_KEY, '-o', 'StrictHostKeyChecking no', '-o', 'BatchMode yes',
                @source, @user + '@' + @address + ':' + @target ]
        @exec cmd, cb
    
# Execute command on remote system over ssh
exports.Ssh = class Ssh extends Worker
    start: ( cb ) ->
        if not @user  then return cb and cb(new Error("Remote user not set"))
        if not @address then return cb and cb(new Error("Remote address not set"))
        if not @command then return cb and cb(new Error("Shell command not set"))
        cmd = ["ssh",'-i', SSH_PRIVATE_KEY, '-o', 'StrictHostKeyChecking no', '-o', 'BatchMode yes', '-l', @user, @address ]
        @exec cmd.concat(@command), cb

#
# Work queue
#
exports.WorkQueue = class WorkQueue extends state.State

    workers: []

    # Create new worker
    worker: ( type, cb ) ->
        id = uuid.v1()
        state.pload 'worker', type, id, (err, worker) =>
            return cb and cb(err) if err
            worker.on 'state',   (state, msg)  => @setState(state, msg)
            worker.on 'failure', (err, worker) => @failure(err, worker)
            worker.on 'success', (err, worker) => @success(err, worker)
            @workers.push worker.id
            @save (err) ->
                return cb and cb( err ) if err
                worker.save (err) ->
                    cb and cb(err, worker)

    start: (cb) ->
        if @workers.length
            state.load 'worker', @workers[0], (err, worker) ->
                worker.start cb

    stop: (cb) ->
        if @workers.length
            state.load 'worker', @workers[0], (err, worker) ->
                worker.stop cb

    failure: (err, worker) ->
        console.log "Worker #{worker.id} failed", err
        @emit 'failure', err, worker
        @workers =  _.without @workers, worker.id
        worker.clear()
        @save()

    success: (err, worker) ->
        console.log "Worker #{worker.id} succeeded"
        @emit 'success', err, worker
        @workers =  _.without @workers, worker.id
        worker.clear()
        @save()
