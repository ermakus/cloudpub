aws     = require 'aws-lib'
account = require './account'

# AWS keys
EC2_ACCESS_KEY='AKIAJRLCT356JGNL55XA'
EC2_SECRET_KEY='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'

# AWS client
EC2 = aws.createEC2Client( EC2_ACCESS_KEY, EC2_SECRET_KEY, secure:false )

# Instance class
exports.Instance = class Instance

    iid: null

    state: 'down'

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
        EC2.call "RunInstances", options, (result) ->
            console.log result
            cb and cb( null, result.instancesSet )

    stop: (cb) ->
        return cb and cb(null) if not @iid
        EC2.call "TerminateInstances", 'InstanceId.0':@iid, (result) ->
            console.log result
            cb and cb( null, result )

exports.list = (cb) ->
    EC2.call "DescribeInstances", {}, (result) ->
        console.log result
        cb and cb( null, result )

exports.create = -> new Instance()

# Init module and requiet handlers
exports.init = (app, cb)->
    app.get '/instancies', account.force_login, (req, resp)->
        exports.list (error, items)->
            resp.render 'instancies', { items,error }
    cb and cb( null )
