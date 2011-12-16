spawn   = require('child_process').spawn
account = require './account'
command = require './command'

state   = require('./state')

SSH_PRIVATE_KEY='/home/anton/.ssh/id_rsa'
RUN_TIMEOUT=500


# Load cloud managers
CLOUDS =
    'ssh':     require './cloud/ssh'
    'ec2':     require './cloud/ec2'

# TODO: read from ~/.ssh/id_rsa.pub
PUBLIC_KEY = 'ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEArReBqZnuNxIKy/xHS2rIuCNOZ0nOmtJyLIr5lnJ26LPD3vRGzrpMNh4e7SKES70cSf8OW/d55G5Xi+VXExdL+ub6j/6++06wJYf63Ts4DFL4UGMlwob0VKS73KiVI1yk5FVKJ8BajaqMvWqSss59XD5bQoLQVdvtKjpaMPjPFMq+m170cRQF7sgf3iGfM9GoKVHU2+B3N6+DUIgX8DTdfikatY70cC8HwI0dl5M2bZbh+pNujij13oeM0zcZcjbrqn2VXt3vuEIhAd/UYp2mRPC+JI7lZAQmkoI+jHKHv2LOOaHC9yXFGpvG8p8yqu4Dbw7JoruDTlXsNoET6D2eow== cloudpub'


#
# Low level system interface
#
exports.Worker = class Worker extends state.State

    # Set address and user for remote system
    constructor: (@user, @address) ->
        super('worker', null )

    # Execute command on local system
    exec: (run, cb) ->
        console.log "Exec " + run.join " "
        stdout = ''
        stderr = ''
        ch = spawn run[0], run[1...]

        @id = @user + '@' + @address + '-' + ch.pid

        timer = setTimeout (=>
            timer = null
            @setState 'maintain', 'Running ' + run[0], cb
        ), RUN_TIMEOUT

        ch.stdout.on 'data', (data) ->
            console.log "SHELL: ", data.toString()
            stdout += data.toString()

        ch.stderr.on 'data', (data) ->
            stderr += data.toString()
            console.log "ERROR: ", data.toString()
        
        ch.on 'exit', (code) =>
            callback = undefined
            if timer
                clearTimeout timer
                callback = cb
            if code == 0
                @setState 'up', 'Command executed', (err)=>
                    return callback and callback(err) if err
                    @clear callback
            else
                @setState 'error', stderr, (err)=>
                    return callback and callback(err) if err
                    @clear (err)->
                        callback and callback( new Error( stderr ) )
     
    # Execute command on remote system (over ssh)
    ssh: ( command, cb ) ->
        cmd = ["ssh",'-i', SSH_PRIVATE_KEY, '-o', 'StrictHostKeyChecking no', '-o', 'BatchMode yes', '-l', @user, @address ]
        @exec cmd.concat(command), cb

    # Copy files to remote system (over scp)
    scp: ( source, target, cb ) ->
        cmd = ["scp", '-r', '-c', 'blowfish', '-C', '-i', SSH_PRIVATE_KEY, '-o', 'StrictHostKeyChecking no', '-o', 'BatchMode yes', source, @user + '@' + @address + ':' + target ]
        @exec cmd, cb


# Instance class
exports.Instance = class Instance extends state.State

    cloud: 'ssh'

    constructor: (id) ->
        super('node',id)

    createWorker: ->
        if not (@user and @address)
            throw new Error("Can't create local worker")
        new Worker(@user, @address)


    # Start instance
    start: (params, cb)->
        if not (@id and @cloud)
            if params.cloud of CLOUDS
                @cloud = params.cloud
            else
                return cb and cb( new Error('Invalud cloud ID: ' + params.cloud) )
        
        @address = params.address
        @user = params.user

        if not (@address and @user)
            return cb and cb( new Error('Invalid address or user' + params.cloud) )
        
        if not @id and (@cloud == 'ssh')
            @id = 'c-' + @address.replace '.','-'
        
        @setState 'maintain', "Installing services", (err) =>
            return cb and cb(err) if err
            CLOUDS[@cloud].install.call @, params, (err) =>
                return cb and cb(err) if err
                @save cb

    # Stop instance
    stop: (params, cb)->
        if params.mode == 'shutdown'
            @setState 'maintain', "Removing data", (err) =>
                return cb and cb(err) if err
                CLOUDS[@cloud].uninstall.call @, params, (err) =>
                    if err
                        @setState "error", err, cb
                    else
                        @setState "down", "Deleted", cb
        else
            @setState "maintain", "In maintaince mode", cb


# Init HTTP request handlers
exports.init = (app, cb)->

    # HTML server list view
    app.get '/instances', (req, resp)->
        resp.render 'instance', {pubkey:PUBLIC_KEY}

    # JSON server list
    app.get  '/api/instances', account.force_login, command.list_handler('instance', (entity, acc, cb ) ->
        # Return instances list in callback
        CLOUDS['ec2'].list (err,inst)->
            result = []
            # Collect SSH nodes from cache
            nodes = state.list('node') or {}
            ec2ids = []
            # Add EC2 nodes
            for item in inst
                if item.state == 'down' then continue
                node = new Instance(item.id)
                node.cloud = 'ec2'
                node.address = item.address
                # Update node state and save to cache
                if item.state != node.state
                    node.setState item.state
                result.push node
                ec2ids.push node.id

            # Add other nodes
            for id of nodes
                cloud = nodes[id].cloud
                # Add SSH nodes
                if cloud == 'ssh'
                    result.push new Instance(id)
                # Remove vanished ec2 nodes
                if cloud == 'ec2' and (id not in ec2ids)
                    old = new Instance(id)
                    old.clear (err)->
                        if err then console.log "CACHE: Error clear ec2 instance: ", err

            cb null, result
    )

    # Server command handler
    app.post '/api/instance/:command', account.ensure_login, command.command_handler('instance',(id,acc) ->
        # Create instance immediately
        if id == 'new' then id = null
        new Instance(id)
    )
    cb and cb( null )
