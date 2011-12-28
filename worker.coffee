spawn   = require('child_process').spawn
_       = require 'underscore'
async   = require 'async'
state   = require './state'
io      = require './io'

log     = console

SSH_PRIVATE_KEY='/home/anton/.ssh/id_rsa'
RUN_TIMEOUT=500
#
# Worker process
#
exports.Worker = class Worker extends state.State

    # Execute command on local system
    exec: (run, cb) ->

        stdout = ''
        stderr = ''

        log.info "Exec " + (run.join " ")
        
        ch = spawn run[0], run[1...]

        @pid = ch.pid

        ch.stdout.on 'data', (data) ->
            log.info "stdout: ", data.toString()
            if stdout.length < 512
                stdout += data.toString()

        ch.stderr.on 'data', (data) ->
            stderr += data.toString()
            log.info "stderr: ", data.toString()
        
        ch.on 'exit', (code) =>
            if code == 0
                @message = stdout
                @emit 'success', @, (err)=>
                    if err
                        log.error "Worker #{@id} success handler error", err
                    else
                        log.info "Worker #{@id} succeed"
            else
                @message = stderr
                @emit 'failure', @, (err)=>
                    if err
                        log.error "Worker #{@id} fail handler error", err
                    else
                        log.error "Worker #{@id} failed", err
        
        cb and cb(null)

    # Kill process and delete worker
    stop: (cb)->
        if (@state=='up') and @pid
            try
                process.kill @pid
            catch err
                log.warn "Process with #{@pid} does not exists"
        @clear cb

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
        log.info "Preproc #{@source} -> #{@target}: " + JSON.stringify @context
        fs.readFile @source, (err, cfg) =>
            if err
                return @emit 'failure', err, @
            cfg = _.template cfg.toString(), @context
            fs.writeFile @target, cfg, (err)=>
                if err
                    return @emit 'failure', err, @
                else
                    return @emit 'success', "Done", @
        cb and cb(null)


exports.Proxy = class Proxy
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
    log = io.log
    cb and cb( null )
