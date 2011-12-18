async   = require 'async'

account = require './account'
command = require './command'
state   = require './state'
worker  = require './worker'

# Instance class
exports.Instance = class Instance extends worker.WorkQueue

    init: ->
        super()

    configure: (params, cb) ->

        @address = params.address
        @user = params.user

        if not (@address and @user)
            return cb and cb( new Error('Invalid address or user' + params.cloud) )
        
        if not @id
            @id = 'i-' + @address.split('.').join('-')
        
        @setState 'maintain', "Configured with #{@user}@#{@address}", cb

    # Start instance
    start: (params, cb) ->
        console.log "CONFIGURE"
        console.trace()
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
        @submit 'copy',
            user:@user
            address:@address
            source:'/home/anton/Projects/cloudpub'
            target:"/home/#{@user}/"
            success: (msg)=> @setState 'up', msg
            failure: (err)=> @setState 'error', err.message

        @setState 'maintain', "Transfering files to #{@address}", cb

    uninstall: (params, cb) ->
        target = '~/cloudpub'
        @submit 'shell',
            user:@user
            address:@address
            command:['rm','-rf', target]
            success:(msg)=> @clear()
            failure:(err)=> @clear()
        
        @setState 'maintain', "Uninstalling files from #{@address}", cb


# Init HTTP request handlers
exports.init = (app, cb)->
    app.register 'instance', (entity, cb)->

        resolve = (item, cb)->
            async.map item.workers, state.load, (err, workers)->
                item.workers = workers
                cb and cb(null, item)

        state.query entity, (err, items)->
            return cb and cb(err) if err
            async.forEach items, resolve, (err)->
                cb and cb(err, items)

     cb and cb( null )
