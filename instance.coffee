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
            @address = nconf.get("node:#{@id}:address") or '127.0.0.1'
        else
            @cloud   = 'ssh'
        console.log "Instance", @

    # Save instance state
    save: (cb) ->
        return cb and cb(null) unless @id
        nconf.set("node:#{@id}:state", @state)
        nconf.set("node:#{@id}:cloud", @cloud)
        nconf.save cb

    setState: ( state, cb) ->
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

# Init module and requiet handlers
exports.init = (app, cb)->
    # List of instancies
    app.get  '/instancies', account.force_login, command.list_handler('instance', (entity, acc, cb ) ->
        # Return instancies list in callback
        CLOUDS['ec2'].list (err,inst)->
            inst = inst.map (item) ->
                node = new Instance(item.id)
                node.cloud = 'ec2'
                node.state = item.state
                node.save (err)->
                    if err
                        console.log "Error to save ec2 instance: ", err
                node
            cb null, inst
    )
    # Instance command
    app.post '/instance/:command', account.ensure_login, command.command_handler('instance',(id,acc) ->
        # Create instance immediately
        if id == 'new' then id = null
        new Instance(id)
    )
    cb and cb( null )
