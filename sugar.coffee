#### Syntax sugar for some frequently used functions

# Dependencies
_     = require 'underscore'
async = require 'async'
assert = require 'assert'
state = require './state'
settings = require './settings'

#### Validate correctness of the function call
#
# Used for fighting callback hell
#
exports.vargs = vargs = (args)->
    try
        #settings.log.trace "Arguments", ("#{typeof(a)}:#{JSON.stringify(a)}" for a in args)
        assert.ok(args.length > 0)
        assert.ok(args[args.length-1])
        assert.ok(_.isFunction(args[args.length-1]))
    catch ex
        settings.log.fatal "Bad arguments", ("#{typeof(a)}:#{JSON.stringify(a)}" for a in args)
        settings.log.fatal item for item in (new Error().stack).split("\n")[2...]
        process.exit(1)

#### Send event to target object by id
#
# This function is send event to the target object, 
# even if object executed on other machine instance
#
# - *name* is name of event
# - *target* ID or array of target(s)
# - *params* Event handler parameters
exports.emit = emit = (name, target, params..., cb=state.defaultCallback)->
    vargs arguments
    # Handle emit to group
    if _.isArray(target)
        return async.forEach target, ((id,cb)->emit(name, id, params..., cb)), cb
    # Load object and handle event
    settings.log.debug "Emit #{name} to \##{target}"
    state.load target, (err, obj)->
        if err
            if err.message.indexOf("Reference not found") == 0
                settings.log.warn "Emit event to missing object", err.message
                return cb(null)
            return cb(err)
        obj.emit(name, params..., cb)


#### Add bi-directional relation between obects
#
# - *name* is name of attribute, that should be array of IDs
# - *from*, *to* is IDs of source and target objects
#
exports.relate = (name, from, to, cb)->
    assert.ok _.isFunction(cb)
    settings.log.debug "Link #{name} from #{from} to #{to}"
    async.waterfall [
        # Load source object
        (cb)=>
            state.load(from, cb)
        # Update from.name array
        (fromObj, cb)=>
            depends = fromObj[name] or []
            if to not in depends
                depends.push(to)
                fromObj[name] = depends
                fromObj.save(cb)
            else
                cb(null)
        # Load target object
        (cb)=>
            state.load(to, cb)
        # Update to._name
        (toObj, cb)=>
            depends = toObj['_' + name] or []
            if from not in depends
                depends.push(from)
                toObj['_' + name] = depends
                toObj.save(cb)
            else
                cb(null)
        ], cb

#### Remove relation
#
# Arguments is the same as in `relate`
#
exports.unrelate = (name, from, to, cb)->
    assert.ok _.isFunction(cb)
    settings.log.debug "Unlink #{name} from #{from} to #{to}"
    async.waterfall [
        # Load source object
        (cb)=>
            state.load(from, cb)
        # Update from.name array
        (fromObj, cb)=>
            depends = fromObj[name] or []
            if to in depends
                depends = _.without depends, to
                fromObj[name] = depends
                fromObj.save(cb)
            else
                cb(null)
        # Load target object
        (cb)=>
            state.load(to, cb)
        # Update to._name
        (toObj, cb)=>
            depends = toObj['_' + name] or []
            if from not in depends
                depends = _.without depends, to
                toObj['_' + name] = depends
                toObj.save(cb)
            else
                cb(null)
        ], (err)->cb(err)

##### Route events from one object to another
#
# - *fromEvent* is name of the event
# - *from* is source object ID
# - *toEvent* is name of handler
# - *to* is target object id
#
exports.route = (fromEvent, from, toEvent, to, cb)->
    assert.ok _.isFunction(cb)
    settings.log.debug "Route event #{fromEvent} from (#{from}) to handler #{toEvent} (#{to})"
    async.waterfall [
            # Load source object
            (cb)->
                state.load(from, cb)
            # Subscribe to event and save
            (fromObj, cb)->
                fromObj.on(fromEvent, toEvent, to)
                fromObj.save(cb)
        ], (err)->cb(err)

#### Remove events routing
#
# Arguments is the same as in `route`
#
exports.unroute = (fromEvent, from, toEvent, to, cb)->
    assert.ok _.isFunction(cb)
    settings.log.debug "Unroute event #{fromEvent} from (#{from}) to handler #{toEvent} (#{to})"
    async.waterfall [
            # Load source object
            (cb)->
                state.load(from, cb)
            # Unsubscribe from event
            (fromObj, cb)->
                fromObj.mute(fromEvent, toEvent, to)
                fromObj.save(cb)
        ], (err)->cb(null)


#### Return state of the group by checking each object
#
# Result is passed in callback as:
#
# - "up" if all children is up
# - "down" if all children is down
# - "error" if at least 1 child error
# - "maintain" if any other
# - or *null* if children is empty
#
exports.groupState = (children, cb)->
    assert.ok _.isFunction(cb)

    if _.isEmpty(children)
        return cb(null,null)

    states = {up:0,maintain:0,down:0,error:0}

    checkState = (id, cb)->
        state.load id, (err, child)->
            # Non-exist children state is error
            if err
                states[ 'error' ] += 1
            else
                states[ child.state ] += 1
            cb(null)

    async.forEach children, checkState, (err)=>
        return cb(err) if err
        if states['up'] == children.length
            return cb(null,'up')
        if states['down'] == children.length
            return cb(null,'down')
        if states['error'] > 0
            return cb(null,'error')
        cb(null, "maintain")

