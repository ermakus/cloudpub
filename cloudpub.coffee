async = require 'async'
service = require './service'

exports.Cloudpub = class Cloudpub extends service.Service
        
    startup: (params, instance, cb) ->
        home = "/home/#{instance.user}/.cloudpub"
        instance.submit 'shell', {
            message: "Starting daemon"
            command:["#{home}/cloudpub/bin/daemon", "-b", "#{home}/cloudpub", "start", @id,
                     "#{home}/runtime/bin/node", "#{home}/cloudpub/server.js", 4000]
            success: (event, cb)=>
                async.series( [
                    (cb)=> @setState('up', "Service started", cb),
                    (cb)=> instance.setState("up", "Server online", cb)], cb)
            failure: (event, cb)=> @setState('error', event.err.message, cb)
        }, cb

    shutdown: (params, instance, cb) ->
        home = "/home/#{instance.user}/.cloudpub"
        instance.submit 'shell', {
            message: "Stop daemon"
            home: "#{home}/cloudpub"
            command:["#{home}/cloudpub/bin/daemon", "stop", @id]
            success: (event, cb)=>
                async.series( [
                    (cb)=> @setState('down', "Daemon stopped", cb),
                    (cb)=> instance.setState("maintain", "Master service stopped", cb)
                ], cb)
            failure: (event, cb)=>
                async.series([
                    (cb)=> @setState('error', err.message, cb),
                    (cb)=> instance.setState("maintain", "Service error", cb)
                ], cb)
        }, cb

    install: (params, instance, cb) ->
        home = "/home/#{instance.user}/.cloudpub"
        async.series [
            # Set instance state
            (cb)=> (instance.stop cb),
            (cb)=> (instance.setState 'maintain', 'Installing service', cb),
            # Sync service files
            (cb)=> (instance.submit 'sync', {
                        message: "Sync service files"
                        source:'/home/anton/Projects/cloudpub'
                        target: "#{home}/"
                        success: (event, cb)=> @setState 'maintain', "Installing runtime", cb
                        failure: (event, cb)=> @setState 'error', event.error.message
                    }, cb),
            # Install service deps
            (cb)=> (instance.submit 'shell', {
                        message: "Install node.js runtime"
                        command:["#{home}/cloudpub/bin/install", "node", "#{home}/runtime"]
                        success: (event, cb)=> @setState 'up', "Runtime installed", cb
                        failure: (event, cb)=> @setState 'error', err.message, cb
                    }, cb),
        ] , cb

    uninstall: (params, instance, cb) ->
        home = "/home/#{instance.user}/.cloudpub"
        instance.submit 'shell', {
            command:['rm','-rf', home]
            success:(event, cb)=> @setState 'down', 'Service down', cb
            failure:(event, cb)=> @setState 'error', event.error.message, cb
        }, cb
