nconf   = require 'nconf'
account = require './account'
command = require './command'

# Load cloud managers
CLOUDS =
    'ssh':     require './cloud/ssh'
    'ec2':     require './cloud/ec2'

# TODO: read from ~/.ssh/id_rsa.pub
PUBLIC_KEY = 'ssh-rsa AAAAB3NzaC1yc2EAAAABIwAAAQEArReBqZnuNxIKy/xHS2rIuCNOZ0nOmtJyLIr5lnJ26LPD3vRGzrpMNh4e7SKES70cSf8OW/d55G5Xi+VXExdL+ub6j/6++06wJYf63Ts4DFL4UGMlwob0VKS73KiVI1yk5FVKJ8BajaqMvWqSss59XD5bQoLQVdvtKjpaMPjPFMq+m170cRQF7sgf3iGfM9GoKVHU2+B3N6+DUIgX8DTdfikatY70cC8HwI0dl5M2bZbh+pNujij13oeM0zcZcjbrqn2VXt3vuEIhAd/UYp2mRPC+JI7lZAQmkoI+jHKHv2LOOaHC9yXFGpvG8p8yqu4Dbw7JoruDTlXsNoET6D2eow== cloudpub'

# Instance class
exports.Instance = class Instance

    state: 'down'

    # Create instance in cloud
    constructor: (@id)->
        if @id
            # Init persisten fields
            @state   = nconf.get("node:#{@id}:state") or 'down'
            @message = nconf.get("node:#{@id}:message")
            @cloud   = nconf.get("node:#{@id}:cloud") or 'ssh'
            @address = nconf.get("node:#{@id}:address")
            @user    = nconf.get("node:#{@id}:user")
        else
            # Unsaved
            @cloud   = 'ssh'

    # Save instance state
    save: (cb) ->
        return cb and cb(null) unless @id
        # Save persistend fields
        nconf.set("node:#{@id}:state",   @state)
        nconf.set("node:#{@id}:message", @message)
        nconf.set("node:#{@id}:cloud",   @cloud)
        nconf.set("node:#{@id}:address", @address)
        nconf.set("node:#{@id}:user",    @user)
        nconf.save cb

    clear: (cb) ->
        if @id
            nconf.clear "node:#{@id}"
            @id = undefined
            nconf.save cb
        else
            cb and cb( null )

    # Update state and save if changed
    setState: (state, message, cb) ->
        if state
            @state = state
        if typeof(message) == 'function'
            cb = message
        else
            @message = message
        @save (err) =>
            if err
                @state = 'error'
                @message = 'State save error: ' + err
            
            console.log "Server #{@id}: [#{@state}] #{@message}"
            cb and cb(err)

    # Start instance
    start: (params, cb)->
        if not (@id and @cloud)
            if params.cloud of CLOUDS
                @cloud = params.cloud
            else
                return cb and cb( new Error('Invalud cloud ID: ' + params.cloud) )
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
            nodes = nconf.get('node') or {}
            ec2ids = []
            # Add EC2 nodes
            for item in inst
                if item.state == 'down' then continue
                node = new Instance(item.id)
                node.cloud = 'ec2'
                node.address = item.address
                # Update node state and save to cache
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
