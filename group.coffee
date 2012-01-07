_       = require 'underscore'
async   = require 'async'
state   = require './state'
tsort   = require './topologicalSort.js'

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
        @save cb

    # Remove children from group
    remove: (id, cb) ->
        if id in @children
            exports.log.info "Remove #{id} from #{@id}"
            @children = _.without @children, id
            @save cb
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
    each: (method, params..., cb)->

        # Call method on instance
        makeCall = (instance, cb)->
            exports.log.info "Call method", method, "params", params
            # Make params copy for each call
            p = _.clone params
            # Append callback
            p.push cb
            instance[method].apply(instance, params)

        # Load children  and call method
        process = (id, cb) ->
            # In case of blueprint we can create object
            state.loadOrCreate id, (err, instance) ->
                return cb and cb(err) if err
                # If object is just created
                if not instance.stump
                    # Save it before call
                    instance.save (err)->
                        return cb(err) if err
                        makeCall(instance, cb)
                else
                    makeCall(instance)

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
            st = 'maintain'
            if states['up'] == children.length
                st = 'up'
            if states['down'] == children.length
                st = 'down'
            if states['error'] > 0
                st = 'error'
           
            cb(null, st)
 
    # Update group state and fire events 
    updateState: (cb)->
        exports.log.info "Update group #{@id} state"
        async.waterfall [
            # Get children state
            (cb)=>
                @groupState(@children,cb)
            # Update group state
            (st, cb)=>
                @setState(st, cb)
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
    start: (params..., cb)->
        async.series [
            (cb) => @each('start', params..., cb)
            (cb) => @updateState(cb)
        ], cb

    # Stop children and update state
    stop: (params..., cb)->
        if typeof(params) == 'function'
            cb = params
            params = {}
        async.series [
            (cb) => @each('stop', params..., cb)
            (cb) => @updateState(cb)
        ], cb

    # Remove with childrens
    deepClear: (cb)->
        async.series [
            (cb) => @each('clear', cb)
            (cb) => @clear(cb)
        ], cb
