#
# Amazon EC2 cloud instance 
#
async    = require 'async'
aws      = require 'aws-lib'
state    = require './state'
instance = require './instance'

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

exports.Ec2 = class Ec2 extends instance.Instance

    startup: (params, cb) ->
        options =
            ImageId:'ami-31814f58'
            MinCount:1
            MaxCount:1
            KeyName:'cloudpub'
            UserData:''
            InstanceType:'t1.micro'
        EC2.call "RunInstances", options, (result) =>
            if err = ec2_error result
                return cb and cb(err)
            else
                insts = ec2_inst_set result
                @id = insts[0].id
                @address = insts[0].address
                @setState insts[0].state, "Starting instance: #{@id}", cb

    start: (params, cb) ->
        if not params.id
            return @startup( params, cb )
        EC2.call "StartInstances", 'InstanceId.0':@id, (result) =>
            if err = ec2_error result
                return cb and cb(err)
            insts = ec2_inst_set result
            @address = insts[0].address
            @setState insts[0].state, "Starting instance: #{@id}", cb

    stop: (params, cb) ->
        if params.mode == 'shutdown'
            @terminate params, cb
        else
            @setState "maintain", "Maintaince mode", cb

    terminate: (params, cb) ->
        return cb and cb(new Error('Node ID not set')) if not @id
        EC2.call "TerminateInstances", 'InstanceId.0':@id, (result) =>
            if err = ec2_error result
                cb and cb(err)
            else
                @setState "maintain", "Terminating instance #{@id}", cb

# List all available instacies
exports.list = list = (cb) ->
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

update_node = (item, cb) ->
    state.load item.id, 'ec2', (err, cached)->
        return cb and cb(null) if err # Not found in cache - just ignore
        if item.state != cached.state or item.address != cached.address
            cached.address = item.address
            cached.state = item.state
            if item.state == 'up'
                return cached.setState item.state, "Instance #{item.id} available", cb
            if item.state == 'down'
                return cached.setState item.state, "Instance #{item.id} down", (err)->
                    cached.clear cb
            cached.setState item.state, "Instance #{item.id} updated"
        else
            cb and cb(null)

exports.update = update = (cb) ->
    list (err, items)->
        if err
            console.log "EC2 query error: ", err
            return
        else
            console.log "EC2 query: ", items

        # Update ec2 cache
        async.forEach items, update_node, (err)->
            if err then return console.log "EC2 update error: ", err
            # Query cache
            state.query 'ec2', (err, cachedItems)->
                if err then return console.log "EC2 query error: ", err
                # Select cached but deleted instancies
                toDelete = cachedItems.filter (item)->
                    for ec2item in items
                        if ec2item.id == item.id
                            if ec2item.state == 'down'
                                return true
                            return false
                    return true
                # Delete instancies from cache
                async.forEach toDelete, ((item, cb)-> item.clear cb), (err)->
                    if err then return console.log "EC2 cache clean error: ", err
                    setTimeout update, 1000 * 5

exports.init = (app, cb) ->
    update()
    cb and cb(null)
