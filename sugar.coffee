_     = require 'underscore'
async = require 'async'
state = require './state'

#
# Syntax sugar for fOOp
#

# Add bi-directional relation between obects
# name = name of attribute
# from, to = object IDs 
exports.relate = (name, from, to, cb)->
    exports.log.debug "Link #{name} from #{from} to #{to}"
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

# Remove relation
exports.unrelate = (name, from, to, cb)->
    exports.log.debug "Unlink #{name} from #{from} to #{to}"
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

# Route events from one object to another
# fromEvent = name of event
# from = source ID
# toEvent = name of handler
# to = target ID
exports.route = (fromEvent, from, toEvent, to, cb)->
    exports.log.debug "Route event #{fromEvent} from (#{from}) to handler #{toEvent} (#{to})"
    async.waterfall [
            # Load source object
            (cb)->
                state.load(from, cb)
            # Update from.name array
            (fromObj, cb)->
                fromObj.on(fromEvent, toEvent, to)
                fromObj.save(cb)
        ], (err)->cb(err)

# Remove events routing
# fromEvent = name of event
# from = source ID
# toEvent = name of handler
# to = target ID
exports.unroute = (fromEvent, from, toEvent, to, cb)->
    exports.log.debug "Unroute event #{fromEvent} from (#{from}) to handler #{toEvent} (#{to})"
    async.waterfall [
            # Load source object
            (cb)->
                state.load(from, cb)
            # Update from.name array
            (fromObj, cb)->
                fromObj.mute(fromEvent, toEvent, to)
                fromObj.save(cb)
        ], (err)->cb(null)

