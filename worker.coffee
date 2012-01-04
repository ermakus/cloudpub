spawn    = require('child_process').spawn
_        = require 'underscore'
async    = require 'async'
state    = require './state'
io       = require './io'
settings = require './settings'

RUN_TIMEOUT=500
#
# Worker process
#
exports.Worker = class Worker extends state.State

    # Execute command on local system
    exec: (run, cb) ->

        stdout = ''
        stderr = ''

        exports.log.info "Exec " + (run.join " ")
        
        options = {
            env: _.clone( process.env )
        }

        ch = spawn run[0], run[1...], options

        @pid = ch.pid

        ch.stdout.on 'data', (data) ->
            exports.log.info "stdout: ", data.toString()
            if stdout.length < 512
                stdout += data.toString()

        ch.stderr.on 'data', (data) ->
            stderr += data.toString()
            exports.log.info "stderr: ", data.toString()
        
        ch.on 'exit', (code) =>
            if code == 0
                @message = stdout
                @emit 'success', @, (err)=>
                    if err
                        exports.log.error "Worker #{@id} success handler error", err
                    else
                        exports.log.info "Worker #{@id} succeed"
            else
                @message = stderr
                @emit 'failure', @, (err)=>
                    if err
                        exports.log.error "Worker #{@id} fail handler error", err
                    else
                        exports.log.error "Worker #{@id} failed"
        
        cb and cb(null)

    # Kill process and delete worker
    stop: (cb)->
        if (@state=='up') and @pid
            try
                process.kill @pid
            catch err
                exports.log.warn "Process with #{@pid} does not exists"
        @clear cb

exports.Sync = class Sync extends Worker
    start: (cb)->
        if not @source  then return cb and cb(new Error("Copy source not set"))
        if not @target  then return cb and cb(new Error("Copy target not set"))
        if not @user    then return cb and cb(new Error("Remote user not set"))
        if not @address then return cb and cb(new Error("Remote address not set"))
        @exec [ __dirname + "/bin/sync", "-u", @user, "-a", @address, "-k", settings.PRIVATE_KEY_FILE, @source, @target ], cb

SSH = "ssh -i #{settings.PRIVATE_KEY_FILE} -o StrictHostKeyChecking=no -o BatchMode=yes"
    
# Execute command on remote system over ssh
exports.Shell = class Shell extends Worker
    start: ( cb ) ->
        if not @user    then return cb and cb(new Error("Remote user not set"))
        if not @address then return cb and cb(new Error("Remote address not set"))
        if not @command then return cb and cb(new Error("Shell command not set"))
        cmd = SSH.split(' ').concat("-l", @user, @address)
        if @home
            cmd = cmd.concat ["export", "PATH=#{@home}/bin:$PATH", '&&', 'cd', @home, '&&']
        else
            exports.log.warn "Shell: Home not set"

        if @context
            context = @context
        else
            context = @

        # Pass environment to children
        if context
            for key of context
                value = context[ key ]
                if _.isString( value ) or _.isNumber( value ) or _.isBoolean( value )
                    cmd.push "export"
                    cmd.push "#{key.toUpperCase()}='#{value}'"
                    cmd.push "&&"

        # Finally add command
        cmd = cmd.concat(@command)
        @exec cmd, cb
