spawn    = require('child_process').spawn
_        = require 'underscore'
async    = require 'async'
state    = require './state'
service  = require './service'
io       = require './io'
settings = require './settings'

# SSH defaults

#
# Service for executing shell command
#
exports.Shell = class Shell extends service.Service

    # Called before start, check configuration here
    configure: ( params, cb ) ->
        if not @user    then return cb(new Error("Remote user not set"))
        if not @address then return cb(new Error("Remote address not set"))
        if not @command then return cb(new Error("Shell command not set"))
        if not @account then return cb(new Error("Account not set"))
        # Load account and take security credentials
        state.load @account, ( err, account )=>
            return cb( err ) if err
            @public_key = account.public_key
            @private_key = account.private_key
            if not @public_key then return cb(new Error("Public key not set"))
            if not @private_key then return cb(new Error("Private key not set"))
            # Call super from anonymous function
            service.Service.prototype.configure.call( @, params, cb )

    # Start shell execution
    startup: ( params, cb) ->
        # Construct SSH command. 
        # Currently, we use SSH also for localhost access, it will be changed in future
        SSH = "ssh -i #{@private_key} -o StrictHostKeyChecking=no -o BatchMode=yes"
        cmd = SSH.split(' ').concat("-l", @user, @address)

        # If home is set chdir before run
        if @home
            cmd = cmd.concat ["export", "NODE_PATH=#{@home}/lib/node_modules", '&&']
            cmd = cmd.concat ["export", "PATH=#{@home}/bin:$PATH", '&&', 'cd', @home, '&&']
        else
            exports.log.warn "Shell: Home not set"

        # If context not set, use this as context
        if @context
            context = @context
        else
            context = @

        # Pass context as environment variables
        if context
            for key of context
                value = context[ key ]
                if _.isString( value ) or _.isNumber( value ) or _.isBoolean( value )
                    cmd.push "export"
                    cmd.push "#{key.toUpperCase().replace('-','_')}='#{value}'"
                    cmd.push "&&"

        # Finally spawn command
        cmd = cmd.concat(@command)
        @spawn cmd, cb

    # Spawn shell command
    spawn: (run, cb) ->

        stdout = ''
        stderr = ''

        exports.log.info "Executing " + (run.join " ")

        options = {
            env: _.clone( process.env )
        }

        # If dry run do not execute command in real
        if settings.DRY_RUN
            process.nextTick =>
                @state = 'down'
                @message = "Dry Run"
                @emit('success', @, state.defaultCallback)
            return @emit('started', @, cb)

        ch = spawn run[0], run[1...], options

        @pid = ch.pid

        ch.stdout.on 'data', (data) ->
            exports.log.stdout data.toString()
            if stdout.length < 32768
                stdout += data.toString()

        ch.stderr.on 'data', (data) ->
            exports.log.stderr data.toString()
            if stderr.length < 32678
                stderr += data.toString()

        ch.on 'exit', (code) =>
            if code == 0
                @message = stdout
                @state = 'down'
                @emit 'success', @, state.defaultCallback
            else
                @message = stderr
                @state = 'error'
                @emit 'failure', @, state.defaultCallback

        @emit('started', @, cb)

    started: (me, cb)->
        @state = 'up'
        @goal = undefined
        @save(cb)

    # Kill process and delete worker
    shutdown: (params, cb)->
        if (@state=='up') and @pid
            try
                process.kill @pid
            catch err
                exports.log.warn "Process with #{@pid} does not exists"
        @emit('stopped', @, cb)

# Sync/copy files
exports.Sync = class Sync extends Shell

    configure: ( params..., cb)->
        if not @source  then return cb(new Error("Copy source not set"))
        if not @target  then return cb(new Error("Copy target not set"))
        @command = [ __dirname + "/bin/sync", "-u", @user, "-a", @address, "-k", @private_key, @source, @target ]
        super( params..., cb )

    startup: ( params, cb)->
        @spawn(@command, cb)

# Generate SSH keypair
exports.Keygen = class Keygen extends Shell

    configure: ( params, cb)->
        if not @public_key  then return cb(new Error("Pubic key not set"))
        if not @private_key  then return cb(new Error("Private key not set"))
        @command = ["ssh-keygen", "-t", "dsa", "-b", "1024", "-N", "\"\"", "-f", @private_key ]
        super( params, cb )

    startup: ( params, cb)->
        @spawn(@command, cb)

