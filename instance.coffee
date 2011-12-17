account = require './account'
command = require './command'
state   = require './state'
worker  = require './worker'

# Instance class
exports.Instance = class Instance extends worker.WorkQueue

    constructor: (entity,id) ->
        # Hold storage entity name
        super('instance', id)

    configure: (params, cb)->

        @address = params.address
        @user = params.user

        if not (@address and @user)
            return cb and cb( new Error('Invalid address or user' + params.cloud) )
        
        if not @id
            @id = 'i-' + @address.split('.').join('-')
        
        @setState 'maintain', "Configured with #{@user}@#{@address}", cb

    # Start instance
    start: (params, cb)->
        @configure params, (err) =>
            return cb and cb(err) if err
            @install params, cb

    # Stop instance
    stop: (params, cb) ->
        if params.mode == 'shutdown'
            @uninstall params, cb
        else
            @setState "maintain", "In maintaince mode", cb

    install: (params, cb) ->
        @worker 'copy', (err,worker) =>
            return cb and cb(err) if err
            worker.user = @user
            worker.address = @address
            worker.source = '/home/anton/Projects/cloudpub'
            worker.target = "/home/#{@user}/"
            worker.on 'success', (msg)=>
                @setState 'up', msg
            worker.on 'failure', (err) =>
                @setState 'error', err.message
            @setState 'maintain', "Transfering files to #{@address}", (err)->
                worker.start cb


    uninstall: (params, cb) ->
        target = '~/cloudpub'
        @worker 'ssh', (err,worker) =>
            return cb and cb(err) if err
            worker.user = @user
            worker.address = @address
            worker.command = ['rm','-rf', target]
            worker.on 'failure', (err) =>
                @setState 'error', err.message
                @clear()
            worker.on 'success', =>
                @setState 'up', 'Server removed successfully'
                @clear()
            @setState 'maintain', "Uninstalling from #{@address}", (err)->
                worker.start cb


# Init HTTP request handlers
exports.init = (app, cb)->
    app.register 'instance'
    cb and cb( null )
