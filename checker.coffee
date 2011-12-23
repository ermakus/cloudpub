state = require './state'

exports.Checker = class Checker extends state.State

    init: ->
        super()
        @expected = []

    expect: (event, cb)->
        @expected.push event
        @save cb

    onState: (event, cb)->
        if not @expected.length or @expected[0] != event.state
            return cb(new Error("Unexpected event:" + JSON.stringify(event)))
        console.log "======================================================="
        console.log "Expected " + event.state + " from " + event.entity + "=" + event.id
        console.log "======================================================="
        @expected = @expected[1...]
        @save cb
