aws     = require 'aws-lib'
account = require './account'
command = require './command'

# AWS keys
EC2_ACCESS_KEY='AKIAJRLCT356JGNL55XA'
EC2_SECRET_KEY='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'

# AWS client
EC2 = aws.createEC2Client( EC2_ACCESS_KEY, EC2_SECRET_KEY, secure:false )

# EC2 statuses -> CloudPub statuses
STATE_EC2LOCAL =
    'running'   : 'up'
    'terminated': 'down'


# Instance class
exports.Instance = class Instance

    id: null

    state: 'down'

    constructor: (@id)->

    start: (params, cb)->
        if not @id
            @createInstance params, cb
        else
            @startInstance params, cb

    createInstance: (params, cb) ->
        options =
            ImageId:'ami-31814f58'
            MinCount:1
            MaxCount:1
            KeyName:'cloudpub'
            UserData:''
            InstanceType:'t1.micro'
        EC2.call "RunInstances", options, (result) ->
            if err = ec2_error result
                cb(err)
            else
                insts = ec2_inst_set result
                console.log insts
                @id = insts[0].id
                @state = inst[0].state
                cb and cb( null, insts )

    startInstance: (params, cb) ->
        return cb and cb(null) if not @id
        EC2.call "StartInstances", 'InstanceId.0':@id, (result) ->
            console.log result
            if err = ec2_error result
                cb(err)
            else
                insts = ec2_inst_set result
                @state = insts[0].state
                cb and cb( null, result )

    stop: (params, cb) ->
        return cb and cb(null) if not @id
        EC2.call "TerminateInstances", 'InstanceId.0':@id, (result) ->
            console.log result
            if err = ec2_error result
                cb(err)
            else
                cb and cb( null, result )

ec2_error = (res) ->
    if errs= res.Errors?.Error
        if errs.constructor != Array
            errs = [errs]
        msg = ''
        for err in errs
            msg += (err.Message + '\n')
        return new Error(msg)
    else
        null
        
ec2_inst_set = (res) ->
    insts = []
    if iset = res.instancesSet?.item
        if iset.constructor != Array
            iset = [iset]
        for ec2inst in iset
            ii = new Instance(ec2inst.instanceId)
            ii.state = STATE_EC2LOCAL[ ec2inst.instanceState?.name ] or 'maintain'
            insts.push ii
    insts

# List all available instacies
exports.list = (cb) ->
    EC2.call "DescribeInstances", {}, (result) ->
        console.log result
        if err = ec2_error result
            cb(err)
        else
            insts = []
            if rset = result.reservationSet?.item
                if rset.constructor != Array
                    rset = [rset]
                for iset in rset
                    insts = insts.concat ec2_inst_set(iset)
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
        if id == 'new' then id = null
        exports.create(id)
    )
    cb and cb( null )
