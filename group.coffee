_        = require 'underscore'
async    = require 'async'
state    = require './state'
tsort    = require './topologicalSort.js'
service  = require './service'
sugar    = require './sugar'
settings = require './settings'

# Object group
exports.Group = class Group extends service.Service

    # Init instance
    init: ->
        super()
        # Children object IDs
        @children = []
        @ready = 0

    # Add children to group
    add: (id, cb=state.defaultCallback) ->
        sugar.vargs arguments
        if id in @children then return cb and cb(null)
        settings.log.debug "Add #{id} to #{@id}"
        @children.push id
        async.series [
                (cb)=> @save(cb)
                (cb)=> sugar.route('*', id, 'serviceState', @id, cb)
            ], (err)->cb(err)

    # Remove children from group
    remove: (id, cb=state.defaultCallback) ->
        sugar.vargs arguments
        if id in @children
            settings.log.debug "Remove #{id} from #{@id}"
            @children = _.without @children, id
            async.series [
                (cb)=> @save(cb)
                (cb)=> sugar.unroute('*', id, 'serviceState',   @id, cb)
            ], (err)->cb(err)
        else
            cb(null)

    # Create and init children
    create: ( params, cb ) ->
        sugar.vargs arguments
        # If array passed then submit all
        if params and _.isArray(params)
            return async.forEachSeries params, ((item, cb)=>@create(item, cb)), cb

        state.loadOrCreate params, (err, worker) =>
            return cb and cb(err) if err

            # Inherit some defaults
            worker.account = @account or worker.account
            worker.user    = @user    or worker.user
            worker.address = @address or worker.address
            worker.home    = @home    or worker.home

            settings.log.debug "Group: Created " + JSON.stringify(worker)

            async.series [
                    # Save worker
                    (cb) => worker.save(cb)
                    # Add worker to childern
                    (cb) => @add(worker.id, cb)
                    # Run if autostart flag passed
                    (cb) ->
                        if worker.autostart
                            worker.start( cb )
                        else
                            cb(null)
                ], (err)->cb(err)

    # Start all children
    startup: (group, cb)->
        sugar.vargs arguments
        settings.log.debug "Group starting", @id
        @ready = 0
        async.series [
            (cb)=>@save(cb)
            (cb)=>@each('start', cb)
        ], cb

    # Stop all children
    shutdown: (group, cb)->
        sugar.vargs arguments
        settings.log.debug "Group stopping", @id
        async.series [
            (cb)=>@each('stop', cb)
            (cb)=>
                if not @children.length
                    @emit 'stopped', @, cb
                else
                    cb(null)
        ], cb

    # Delete group and children
    clear: (cb)->
        sugar.vargs arguments
        async.series [
            (cb) => @each('clear', cb)
            (cb) => Group.__super__.clear.call( @, cb )
        ], (err)->cb(err)

    # Reorder with dependency topological sort
    reorder: (cb)->
        sugar.vargs arguments
        async.map @children, state.load, (err, services)=>
            reordered = []
            for index in tsort.topologicalSort( services )
                reordered.unshift @children[index]
            settings.log.debug "Group new order", reordered
            @children = reordered
            @save(cb)

    # Call method for each children
    each: (method, params..., cb)->
        sugar.vargs arguments
        # Load target and call method
        process = (id, cb) =>
            # In case of blueprint we can create object
            state.load id, (err, instance) =>
                return cb(err) if err
                # If object is just created
                settings.log.debug "Call method", method, "of", instance.id
                instance[method](params..., cb)

        async.forEach @children, process, (err)->
            cb(err)

    # Update group state and fire events
    serviceState: ( name, params..., cb)->
        sugar.vargs arguments
        return cb(null) if name not in ['success', 'failure', 'state']
        # If children success or failure, increase ready count
        service = params[0]
        async.waterfall [
            # Get children state
            (cb)=>
                sugar.groupState(@children,cb)
            # Update group state
            (st, cb)=>
                # Handle empty group state
                st ||= (if @goal == 'start' then 'up' else 'down')
                # Emit state event
                @setState(st, service.message, cb)
            # Fire success
            (cb)=>
                @ready += 1
                settings.log.debug "Group state", @id, @state, @ready
                # Fire group event only when all children is done
                if name == 'state' or @ready != @children.length
                    return cb(null)
                # Do not fire same state twice
                if (@state == 'up')
                    settings.log.debug "Group #{@id} started"
                    return Group.__super__.startup.call( @, @, cb )
                if (@state == 'down')
                    settings.log.debug "Group #{@id} stopped"
                    return Group.__super__.shutdown.call( @, @, cb )
                if (@state == 'error')
                    settings.log.error "Group #{@id} failure"
                    return @emit('failure', @, cb)
                cb(null)

        ], (err)->cb(err)

    continue: (event, cb)->
        sugar.vargs arguments
        cb(null)
