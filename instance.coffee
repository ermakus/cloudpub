nconf   = require 'nconf'
account = require './account'
command = require './command'

# Load cloud managers
CLOUDS =
    'ssh':     require './cloud/ssh'
    'ec2':     require './cloud/ec2'

# Instance class
exports.Instance = class Instance

    id: null
    state: 'down'
    address: null
    privateKey: null

    # Create instance in cloud
    constructor: (@id)->
        if @id
            @cloud   = nconf.get("node:#{@id}:cloud") or 'ssh'
            @state   = nconf.get("node:#{@id}:state") or 'down'
            @address = nconf.get("node:#{@id}:address")
            @user    = nconf.get("node:#{@id}:user")
        else
            @cloud   = 'ssh'
        console.log "Instance", @

    # Save instance state
    save: (cb) ->
        return cb and cb(null) unless @id
        nconf.set("node:#{@id}:state",   @state)
        nconf.set("node:#{@id}:cloud",   @cloud)
        nconf.set("node:#{@id}:address", @address)
        nconf.set("node:#{@id}:user",    @user)
        nconf.save cb

    clear: (cb) ->
        if @id
            console.log "Clear ", @
            nconf.clear "node:#{@id}"
            @id = null
            nconf.save cb
        else
            cb and cb( null )

    # Update state and save if changed
    setState: (state, cb) ->
        @state = state
        @save cb

    # Start instance
    start: (params, cb)->
        if not (@id and @cloud)
            if params.cloud of CLOUDS
                @cloud = params.cloud
            else
                return cb and cb( new Error('Invalud cloud ID: ' + params.cloud) )
        @setState 'maintain', (err) =>
            return cb and cb(err) if err
            CLOUDS[@cloud].install.call @, params, (err) =>
                return cb and cb(err) if err
                @save cb

    # Start instance
    stop: (params, cb)->
        @setState 'maintain', (err) =>
            return cb and cb(err) if err
            CLOUDS[@cloud].uninstall.call @, params, (err) =>
                return cb and cb(err) if err
                @save cb


# Init HTTP request handlers
exports.init = (app, cb)->

    # List of nodes
    app.get  '/instancies', account.force_login, command.list_handler('instance', (entity, acc, cb ) ->
        # Return instancies list in callback
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
                node.setState item.state, (err)->
                    if err then console.log "CACHE: Error save ec2 instance: ", err
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

    # Node command
    app.post '/instance/:command', account.ensure_login, command.command_handler('instance',(id,acc) ->
        # Create instance immediately
        if id == 'new' then id = null
        new Instance(id)
    )
    cb and cb( null )
