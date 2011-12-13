aws     = require 'aws-lib'
account = require './account'

# AWS keys
EC2_ACCESS_KEY='AKIAJRLCT356JGNL55XA'
EC2_SECRET_KEY='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'

# AWS client
EC2 = aws.createEC2Client( EC2_ACCESS_KEY, EC2_SECRET_KEY, secure:false )

# Instance class
exports.Instance = class Instance

    id: null

    state: 'down'

    constructor: (@id)->

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
        return cb and cb(null) if not @id
        EC2.call "TerminateInstances", 'InstanceId.0':@id, (result) ->
            console.log result
            cb and cb( null, result )

exports.list = (cb) ->
    EC2.call "DescribeInstances", {}, (result) ->
        console.log result
        insts = []
        for id of result.instancesSet
            inst = result.instancesSet[id]
            insts.push new Instance(id)
        cb and cb( null, insts )

exports.create = (id) -> new Instance(id)

# Init module and requiet handlers
exports.init = (app, cb)->
    app.get '/instancies', account.force_login, (req, resp)->
        if req.param('type') == 'inline'
            template = 'instancies-table'
            layout = false
        else
            template = 'instancies'
            layout = true
        exports.list (error, items)->
            resp.render  template, { items,layout,error }
    cb and cb( null )
