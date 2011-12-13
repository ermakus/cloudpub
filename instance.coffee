aws     = require 'aws-lib'
account = require './account'
command = require './command'

# AWS keys
EC2_ACCESS_KEY='AKIAJRLCT356JGNL55XA'
EC2_SECRET_KEY='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'

# AWS client
EC2 = aws.createEC2Client( EC2_ACCESS_KEY, EC2_SECRET_KEY, secure:false )

STATE_EC2LOCAL =
    'running':'up'
    'shutting-down':'maintain'
    'terminated':'down'

# Instance class
exports.Instance = class Instance

    id: null

    state: 'down'

    constructor: (@id, @ec2)->
        if @ec2
            @state = STATE_EC2LOCAL[ @ec2.instanceState.name ]

    start: (params, cb)->
        options =
            ImageId:'ami-31814f58'
            MinCount:1
            MaxCount:1
            KeyName:'cloudpub'
            UserData:''
            InstanceType:'t1.micro'
        EC2.call "RunInstances", options, (result) ->
            console.log result
            cb and cb( null, result.instancesSet )

    stop: (params, cb) ->
        return cb and cb(null) if not @id
        EC2.call "TerminateInstances", 'InstanceId.0':@id, (result) ->
            console.log result
            cb and cb( null, result )

# List all available instacies
exports.list = (cb) ->
    EC2.call "DescribeInstances", {}, (result) ->
        insts = []
        for rr in result.reservationSet?.item
            if inst = rr.instancesSet?.item
                insts.push new Instance(inst.instanceId, inst)
        cb and cb( null, insts )

exports.create = (id) -> new Instance(id)

# Init module and requiet handlers
exports.init = (app, cb)->
    # List of instancies
    app.get  '/instancies', account.force_login, command.list_handler('instance', (entity, acc, cb ) ->
        # Return instancies list in callback
        exports.list cb
    )
    # Instance command
    app.post '/instance/:command', account.ensure_login, command.command_handler('instance',(id,acc) ->
        # Create instance immediately
        exports.create(id)
    )
    cb and cb( null )
