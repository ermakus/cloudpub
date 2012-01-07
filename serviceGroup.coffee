_       = require 'underscore'
async   = require 'async'
group   = require './group'
state   = require './state'

#
# Service group
# 
exports.ServiceGroup = class ServiceGroup extends group.Group

    # Create, configure and start services
    # passed as params.services
    start: (params..., cb) ->
        exports.log.info "Start service group", @id
        @mode = "start"
        @mute 'success', 'suicide', @id
        @mute 'failure', 'suicide', @id
        super(params..., cb)

    # Stop service group
    # Accepted params:
    # data = (keep|delete) Keep or delete data and group itself after shutdown
    stop: (params..., cb) ->
        exports.log.debug "Stop service group #{@id}"

        @mode = "shutdown"

        doUninstall = params.data == 'delete'
        if doUninstall
            # Subscribe suicide event handler
            @on 'failure', 'suicide', @id
            @on 'success', 'suicide', @id
        
        async.series [
            # Save
            (cb)=> @save(cb)
            # Call parent stop method
            (cb)=> group.Group.prototype.stop.call(@, params..., cb)
        ], cb

    # Service state event handler
    serviceState: (event, cb)->
        exports.log.debug "Service group state", event.state, event.message
        # Update group state from services
        @updateState event.state, event.message, (err)=>
            return cb(err) if err
            # If group starting up or shutting down, repeat this
            if @mode == 'startup' and @state != 'up'
                return @start(cb)
            if @mode == 'shutdown' and @state != 'down'
                return @stop(cb)
            cb(null)
 
    # Service state handler called when uninstall. 
    # Commits suicide after work complete
    suicide: (app, cb)->
        exports.log.info "Suicide service group: #{@id}"
        # Delete object on next tick
        process.nextTick =>
            async.series [
                (cb) => @each 'clear', cb
                (cb) => @setState 'down', 'Deleted', cb
                (cb) => @clear(cb)
            ], cb
        cb(null)
