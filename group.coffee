_       = require 'underscore'
async   = require 'async'
state   = require './state'
tsort   = require './topologicalSort.js'
sugar   = require './sugar'

# Object group
exports.Group = class Group extends state.State

    # Init instance
    init: ->
        super()
        # Children object IDs
        @children = []

    # Add children to group
    add: (id, cb) ->
        if id in @children then return cb and cb(null)
        exports.log.info "Add #{id} to #{@id}"
        @children.push id
        async.series [
                (cb)=> sugar.route('state',   id, 'updateState', @id, cb)
                (cb)=> sugar.route('started', id, 'continue', @id, cb)
                (cb)=> sugar.route('stopped', id, 'continue', @id, cb)
                (cb)=> @save cb
            ], (err)->cb(err)

    # Remove children from group
    remove: (id, cb) ->
        if id in @children
            exports.log.info "Remove #{id} from #{@id}"
            @children = _.without @children, id
            async.series [
                (cb)=> sugar.unroute('state', id, 'updateState', @id, cb)
                (cb)=> sugar.unroute('started', id, 'continue', @id, cb)
                (cb)=> sugar.unroute('stopped', id, 'continue', @id, cb)
                (cb)=> @save cb
            ], (err)->cb(err)
        else
            cb and cb(null)

    # Reorder with dependency topological sort
    reorder: (cb)->
        async.map @children, state.load, (err, services)=>
            reordered = []
            for index in tsort.topologicalSort( services )
                reordered.unshift @children[index]
            exports.log.info "New order", reordered
            @children = reordered
            @save(cb)

    # Call method for each children
    each: (method, params, cb)->
    
        if(typeof(params)=='function')
            cb = params
            params=undefined

        # Load target and call method
        process = (id, cb) =>
            # In case of blueprint we can create object
            state.load id, (err, instance) =>
                return cb(err) if err
                # If object is just created
                exports.log.debug "Call method", method, "of", instance.id
                if params
                    instance[method](params, cb)
                else
                    instance[method](cb)

        async.forEach @children, process, (err)->
            cb(err)

    # Create and init children
    create: ( params, cb ) ->
        # If array passed then submit all
        if params and _.isArray(params)
            return @createAll(params, cb)
        
        exports.log.info "Group: Create " + JSON.stringify(params)

        state.loadOrCreate params, (err, worker) =>
            return cb and cb(err) if err

            # Inherit some defaults
            worker.user    = @user    or worker.user
            worker.address = @address or worker.address
            worker.home    = @home    or worker.home

            async.waterfall [
                    (cb) => worker.save(cb)
                    (cb) => @add(worker.id, cb)
                ], (err)->cb(err)

    # Submit job list
    createAll: ( list, cb ) ->
        async.forEachSeries list, ((item, cb)=>@create(item, cb)), cb


    # Update group state and fire events 
    updateState: (event, cb)->
        exports.log.info "Update group state", @id, event.message
        async.waterfall [
            # Get children state
            (cb)=>
                sugar.groupState(@children,cb)
            # Update group state
            (st, cb)=>
                st ||= 'up' # Empty group is in up state
                @setState(st, event.message, cb)
            # Fire success
            (cb)=>
                if (@state == 'up') and (@goal == 'start')
                    exports.log.info "Group #{@id} started"
                    return @emit('success', @, cb)
                if (@state == 'down') and (@goal == 'stop')
                    exports.log.info "Group #{@id} stopped"
                    return @emit('success', @, cb)
                cb(null)
            # Fire failure
            (cb)=>
                if @state == 'error'
                    exports.log.error "Group #{@id} failure"
                    @emit('failure', @, cb)
                else
                    cb(null)
        ], cb

    # Resolve children IDs to objects from storage
    # TODO: fix ugly _children
    resolve: (cb)->
        async.map @children, state.load, (err, items)=>
            return cb and cb(err) if err
            @_children = items
            cb and cb(null)

    # Start children and update state
    start: (event, cb)->
        exports.log.info "Group start", @id
        @goal = 'start'
        @each('start', event, cb)

    # Stop children and update state
    stop: (event, cb)->
        exports.log.info "Group stop", @id
        @goal = 'stop'
        @each('stop', event, cb)

    # Group successed
    continue: (event, cb)->
        if @goal == 'start'
            # Restart group until all services is up
            process.nextTick => @start(state.defaultCallback)
        if @goal == 'stop'
            # Stop group until all services is down
            process.nextTick => @stop(state.defaultCallback)
        cb(null)

    # Remove with childrens
    deepClear: (cb)->
        async.series [
            (cb) => @each('clear', cb)
            (cb) => @clear(cb)
        ], (err)->cb(err)
