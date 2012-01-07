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
        @on 'success', 'serviceState', @id
        @on 'failure', 'serviceState', @id
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
        # Update group state from services
        @updateState event.state, event.message, (err)=>
            exports.log.debug "Service group state", @state, @message
            return cb(err) if err
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
