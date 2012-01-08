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
                (cb)=> sugar.route('state', id, 'updateState', @id, cb)
                (cb)=> sugar.route('started', id, 'start', @id, cb)
                #(cb)=> sugar.route('failure', id, 'updateState', @id, cb)
                (cb)=> @save cb
            ], (err)->cb(err)

    # Remove children from group
    remove: (id, cb) ->
        if id in @children
            exports.log.info "Remove #{id} from #{@id}"
            @children = _.without @children, id
            async.series [
                (cb)=> sugar.unroute('state', id, 'updateState', @id, cb)
                #(cb)=> sugar.unroute('success', id, 'updateState', @id, cb)
                #(cb)=> sugar.unroute('failure', id, 'updateState', @id, cb)
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
    each: (method, params..., cb=state.defaultCallback)->

        # Call method on instance
        makeCall = (instance, cb)->
            exports.log.info "Call method", method, "params", params
            instance[method].call(instance, params..., cb)

        # Load children  and call method
        process = (id, cb) =>
            # In case of blueprint we can create object
            state.loadOrCreate id, (err, instance) =>
                return cb and cb(err) if err
                # If object is just created
                if not instance.stump
                    # Swap blueprint by created object ID
                    @children[ @children.indexOf( id ) ] = instance.id
                    # Save it before call
                    instance.save (err)->
                        return cb(err) if err
                        makeCall(instance, cb)
                else
                    makeCall(instance, cb)

        async.forEach @children, process, cb


    # Return group state from children states
    # up       = all children is up
    # down     = all children is down
    # error    = at least 1 child error
    # maintain = any other
    # result state passed to callback
    groupState: (children, cb)->
        states   = {up:0,maintain:0,down:0,error:0}

        checkState = (id, cb)->
            state.load id, (err, child)->
                # Non-exist children in error state
                if err
                    states[ 'error' ] += 1
                else
                    states[ child.state ] += 1
                cb and cb(null)

        async.forEach children, checkState, (err)=>
            return cb and cb(err) if err
            if states['up'] == children.length
                return cb(null,'up')
            if states['down'] == children.length
                return cb(null,'down')
            if states['error'] > 0
                return cb(null,'error')
            cb(null, "maintain")
 
    # Update group state and fire events 
    updateState: (event, cb)->
        exports.log.info "Update group #{@id} state", event.message
        async.waterfall [
            # Get children state
            (cb)=>
                @groupState(@children,cb)
            # Update group state
            (st, cb)=>
                @setState(st, event.message, cb)
            # Fire success
            (cb)=>
                if @state == 'up'
                    exports.log.info "Group #{@id} success"
                    @emit('success', @, cb)
                else
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
    success: (event, cb)->
        if @goal == 'start'
            process.nextTick => @start('start',@,state.defaultCallback)
        cb(null)

    # Remove with childrens
    deepClear: (cb)->
        async.series [
            (cb) => @each('clear', cb)
            (cb) => @clear(cb)
        ], cb
