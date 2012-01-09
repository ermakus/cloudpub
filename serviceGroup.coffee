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
                # Subscribe to suicide if unistall
                @on 'success', 'suicide', @id
            else
                @mute 'success', 'suicide', @id

        async.series [
            # Save
            (cb)=> @save(cb)
            # Call parent stop method
            (cb)=> group.Group.prototype.stop.call(@, params, cb)
        ], cb

    # Service state handler called when uninstall. 
    # Commits suicide after work complete
    suicide: (event, cb)->
        exports.log.info "Suicide service group: #{@id}", cb
        # Delete object on next tick
        process.nextTick =>
            async.series [
                    (cb) => @each('clear', cb)
                    (cb) => @setState('delete', 'Deleted', cb)
                    (cb) => @clear(cb)
                ], (err)->
                    if err then exports.log.error "Suicide failed", err.message

        cb(null)
