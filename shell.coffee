spawn    = require('child_process').spawn
_        = require 'underscore'
async    = require 'async'
state    = require './state'
service  = require './service'
io       = require './io'
settings = require './settings'

# SSH defaults
SSH = "ssh -i #{settings.PRIVATE_KEY_FILE} -o StrictHostKeyChecking=no -o BatchMode=yes"

#
# Service for executing shell command
#
exports.Shell = class Shell extends service.Service

    # Check configuration
    configure: ( params..., cb ) ->
        if not @user    then return cb(new Error("Remote user not set"))
        if not @address then return cb(new Error("Remote address not set"))
        if not @command then return cb(new Error("Shell command not set"))
        super( params..., cb)

    # Start shell execution
    startup: (service, cb) ->
        cmd = SSH.split(' ').concat("-l", @user, @address)

        # If home is set chdir before run
        if @home
            cmd = cmd.concat ["export", "PATH=#{@home}/bin:$PATH", '&&', 'cd', @home, '&&']
        else
            exports.log.warn "Shell: Home not set"

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
    shutdown: (service, cb)->
        if (@state=='up') and @pid
            try
                process.kill @pid
            catch err
                exports.log.warn "Process with #{@pid} does not exists"
        @emit('stopped', @, cb)

# Sync files service
exports.Sync = class Sync extends Shell

    configure: ( params..., cb)->
        if not @source  then return cb(new Error("Copy source not set"))
        if not @target  then return cb(new Error("Copy target not set"))
        @command = [ __dirname + "/bin/sync", "-u", @user, "-a", @address, "-k", settings.PRIVATE_KEY_FILE, @source, @target ]
        super( params..., cb )

    startup: (service, cb)->
        @spawn(@command, cb)

