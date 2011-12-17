#
# Amazon EC2 cloud manager
#

aws      = require 'aws-lib'

# AWS keys
EC2_ACCESS_KEY='AKIAJRLCT356JGNL55XA'
EC2_SECRET_KEY='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'

# AWS client
EC2 = aws.createEC2Client( EC2_ACCESS_KEY, EC2_SECRET_KEY, secure:false )

# EC2 statuses -> CloudPub statuses
STATE_EC2LOCAL =
    'running'   : 'up'
    'terminated': 'down'

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
            ii =  id:ec2inst.instanceId
            ii.state = STATE_EC2LOCAL[ ec2inst.instanceState?.name ] or 'maintain'
            ii.address = if typeof(ec2inst.dnsName) == 'string' then ec2inst.dnsName else null
            insts.push ii
    insts

exports.install = (params, cb) ->
    
    if @id
        return exports.start.call @, params, cb

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
            @id = insts[0].id
            @state = insts[0].state
            @address = insts[0].address
            cb and cb( null, insts )

exports.start = (params, cb) ->
    return cb and cb(new Error('Node ID not set')) if not @id
    EC2.call "StartInstances", 'InstanceId.0':@id, (result) ->
        if err = ec2_error result
            cb(err)
        else
            insts = ec2_inst_set result
            @state = insts[0].state
            @address = insts[0].address

exports.stop = (params, cb) ->
    cb and cb(null)

exports.uninstall = (params, cb) ->
    return cb and cb(new Error('Node ID not set')) if not @id
    EC2.call "TerminateInstances", 'InstanceId.0':@id, (result) ->
        if err = ec2_error result
            cb(err)
        else
            cb and cb( null, result )

# List all available instacies
exports.list = (cb) ->
    EC2.call "DescribeInstances", {}, (result) ->
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


