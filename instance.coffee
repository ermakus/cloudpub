aws = require 'aws-lib'

# AWS keys
EC2_ACCESS_KEY='AKIAJRLCT356JGNL55XA'
EC2_SECRET_KEY='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'

# AWS client
EC2 = aws.createEC2Client( EC2_ACCESS_KEY, EC2_SECRET_KEY, secure:false )

# Instance class
exports.Instance = class Instance
    constructor: ->
        @iid = null

    start: (cb)->
        options =
            ImageId:'ami-31814f58'
            MinCount:1
            MaxCount:1
            KeyName:'cloudpub'
            UserData:''
            InstanceType:'t1.micro'
        ec2.call "RunInstances", options, (result) ->
            console.log result
            cb and cb( null, result.instancesSet )

    stop: (cb) ->
        return cb and cb(null) if not @iid
        ec2.call "TerminateInstances", 'InstanceId.0':@iid, (result) ->
            console.log result
            cb and cb( null, result )

exports.list = (cb) ->
    ec2.call "DescribeInstances", {}, (result) ->
        console.log result
        cb and cb( null, result )

exports.create = -> new Instance()
