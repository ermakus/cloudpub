spawn   = require('child_process').spawn
nconf   = require 'nconf'
# Worker process

exports.Worker = Worker = class
    # Init instance
    constructor: (@wid, @service)->
        if not @wid then throw new Error('No worker ID set')
        if not @service then throw new Error('No service set with worker')
        @pid = nconf.get "worker:#{@wid}:pid" or 0

    # Save worker state (PID, etc)
    save: (cb)->
        nconf.set "worker:#{@wid}:pid", @pid
        nconf.save cb

    # Start process and pass port to it
    start: (cb)->
        console.log "Start worker #{@wid} on port #{@service.port}"
        # Spawn process
        child = spawn "node", ["server.js", @service.port], cwd:@service.home
        # Attach to stdio/out
        child.stderr.on 'data', (data) -> console.log data.toString()
        child.stdout.on 'data', (data) -> console.log data.toString()
        # Wait 500ms to start app and fire success event if all ok
        timer = setTimeout (=>
            timer = null
            @pid = child.pid
            @save cb ), 500
        # Process exit handler
        child.on 'exit', (code, signal) =>
            @pid = 0
            if not timer
                # If success already fired change service state silently
                @service.setState 'maintain', (err) ->
                    if err then console.log "Set state error: #{err}"
            else
                # Else clear success timer and fire error
                clearTimeout timer
                cb and cb( new Error('Worker terminated due to signal ' + signal ) )

    # Stop process
    stop: (cb)->
        console.log "Stop worker #{@wid} on port #{@service.port}"
        if @pid
            console.log "Sending kill signal to PID #{@pid}"
            try
                process.kill @pid, 'SIGHUP'
            catch err
                console.log "Kill failed with error: #{err}"
            @pid = 0
            # Save worker state
            @save cb
        else
            cb and cb( null )


exports.create = (wid, service) -> new Worker(wid, service)
