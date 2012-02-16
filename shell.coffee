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

    # Called before startup, check configuration here
    configure: ( params..., cb ) ->
        if not @command then return cb(new Error("Shell command not set"))
        # If remote call is required
        if @address
            exports.log.info "Shell: Remote exec on #{@address}"
            # ensure we have associated posix user and account
            if not @user then return cb(new Error("Shell: Remote user not set"))
            if not @account then return cb(new Error("Account not set"))
            # then load account and get security credentials
            state.load @account, ( err, account )=>
                return cb( err ) if err
                @public_key = account.public_key
                @private_key = account.private_key
                if not @public_key then return cb(new Error("Shell: Public key not set"))
                if not @private_key then return cb(new Error("Shell: Private key not set"))
                # Call super from the anonymous function
                service.Service.prototype.configure.call( @, params..., cb )
        else
            exports.log.info "Shell: Local exec of #{@command[0]}"
            # Call super
            super( params..., cb )


    # Start shell execution
    startup: ( params, cb) ->
        # We can candle remote execution with ssh
        if @address and not @local
            # Construct SSH command for remote run
            cmd = ["ssh", "-i", @private_key, "-o", "StrictHostKeyChecking=no", "-o", "BatchMode=yes", "-l", @user, @address]
        else
            # else we use default shell
            cmd = []

        # Chdir to home if it defined
        if @home
            cmd = cmd.concat ["cd", @home, '&&']
        else
            exports.log.warn "Shell: Home not set"

        # Prepare the run environment by env command
        cmd.push '/usr/bin/env'

        # If home is set, add some system vars
        if @home
            cmd = cmd.concat ["NODE_PATH=#{@home}/lib/node_modules", "PATH=#{@home}/bin:$PATH"]

        # If context not set, use 'this' as context
        if @context
            context = @context
        else
            context = @

        # Pass context properties as environment variables
        # key names passed in upper case with '-' changed to '_'
        if context
            for key of context
                value = context[ key ]
                if _.isString( value ) or _.isNumber( value ) or _.isBoolean( value )
                    cmd.push "#{key.toUpperCase().replace('-','_')}='#{value}'"

        # Finally concat command and spawn
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

    # Process started
    started: (me, cb)->
        @state = 'up'
        @goal = undefined
        @save(cb)

    # Kill process
    # TODO: support remote processes
    shutdown: (params, cb)->
        if (@state=='up') and @pid
            try
                process.kill @pid
            catch err
                exports.log.warn "Process with #{@pid} does not exists"
        @emit('stopped', @, cb)

#### Sync service
#
# Sync to remote location
#
exports.Sync = class Sync extends Shell

    configure: ( params..., cb)->
        if not @source  then return cb(new Error("Copy source not set"))
        if not @target  then return cb(new Error("Copy target not set"))
        # Dirty tricks here
        # Suppress chdir to home and remote execution
        @home = undefined
        # stub to pass validation
        @command = ['dummy']
        super( params..., cb )

    startup: (params..., cb)->
        # Force local execution
        @local = true
        # Exec sync script
        @command = [ __dirname + "/bin/sync", "-u", @user, "-a", @address, "-k", @private_key, @source, @target ]
        super( params..., cb)

#### Keygen service
#
# Generate SSH keypair
#
exports.Keygen = class Keygen extends Shell

    configure: ( params..., cb)->
        if not @private_key  then return cb(new Error("Private key not set"))
        if not @public_key then return cb(new Error("Pubic key not set"))
        @command = [ __dirname + "/bin/keygen", @private_key, @public_key ]
        super( params..., cb )

