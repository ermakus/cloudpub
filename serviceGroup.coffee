_       = require 'underscore'
async   = require 'async'
group   = require './group'
state   = require './state'

#
# Service group
# 
exports.ServiceGroup = class ServiceGroup extends group.Group

    # Stop service group
    # Accepted params:
    # data = (keep|delete) Keep or delete data and group itself after shutdown
    stop: (params, cb) ->
        exports.log.debug "Stop service group #{@id}"

        if params.data
            params.doUninstall = (params.data == 'delete')

        if params.doUninstall
            # Subscribe suicide event handler
            @on 'failure', 'suicide', @id
            @on 'success', 'suicide', @id
        
        async.series [
            # Save
            (cb)=> @save(cb)
            # Call parent stop method
            (cb)=> group.Group.prototype.stop.call(@, params, cb)
        ], cb

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
