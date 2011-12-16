account = require './account'
command = require './command'
state   = require './state'
worker  = require './worker'

# Load cloud managers
CLOUDS =
    'ssh':     require './cloud/ssh'
    'ec2':     require './cloud/ec2'

# TODO: read from ~/.ssh/id_rsa.pub
PUBLIC_KEY = 'ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEArReBqZnuNxIKy/xHS2rIuCNOZ0nOmtJyLIr5lnJ26LPD3vRGzrpMNh4e7SKES70cSf8OW/d55G5Xi+VXExdL+ub6j/6++06wJYf63Ts4DFL4UGMlwob0VKS73KiVI1yk5FVKJ8BajaqMvWqSss59XD5bQoLQVdvtKjpaMPjPFMq+m170cRQF7sgf3iGfM9GoKVHU2+B3N6+DUIgX8DTdfikatY70cC8HwI0dl5M2bZbh+pNujij13oeM0zcZcjbrqn2VXt3vuEIhAd/UYp2mRPC+JI7lZAQmkoI+jHKHv2LOOaHC9yXFGpvG8p8yqu4Dbw7JoruDTlXsNoET6D2eow== cloudpub'

# Instance class
exports.Instance = class Instance extends worker.WorkQueue

    cloud: 'ssh'

    constructor: (id) ->
        super('instance', id)

    configure: (params, cb)->

        if not (@id and @cloud)
            if params.cloud of CLOUDS
                @cloud = params.cloud
            else
                return cb and cb( new Error('Invalud cloud ID: ' + params.cloud) )

        console.log "CONFIGURE", @

        @address = params.address
        @user = params.user

        if not (@address and @user)
            return cb and cb( new Error('Invalid address or user' + params.cloud) )
        
        if not @id and (@cloud == 'ssh')
            @id = 'c-' + @address.replace '.','-'
        
        @setState 'maintain', "Configured with #{@user}@#{@address}", cb

    # Start instance
    start: (params, cb)->
        @configure params, (err) =>
            return cb and cb(err) if err
            @install params, cb

    # Stop instance
    stop: (params, cb) ->
        if params.mode == 'shutdown'
            @uninstall params, cb
        else
            @setState "maintain", "In maintaince mode", cb

    install: (params, cb) ->
        @worker 'copy', (err,worker) =>
            return cb and cb(err) if err
            worker.user = @user
            worker.address = @address
            worker.source = '/home/anton/Projects/cloudpub'
            worker.target = "/home/#{@user}/"
            worker.on 'success', (msg)=>
                @setState 'up', msg
            worker.on 'failure', (err) =>
                @setState 'error', err.message
            @setState 'maintain', "Transfering files to #{@address}", (err)->
                worker.start cb


    uninstall: (params, cb) ->
        target = '~/cloudpub'
        @worker 'ssh', (err,worker) =>
            return cb and cb(err) if err
            worker.user = @user
            worker.address = @address
            worker.command = ['rm','-rf', target]
            worker.on 'failure', (err) =>
                @setState 'error', err.message
                @clear()
            worker.on 'success', =>
                @setState 'up', 'Server removed successfully'
                @clear()
            @setState 'maintain', "Uninstalling from #{@address}", (err)->
                worker.start cb

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
            nodes = state.list('instance') or {}
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
