state = require '../state'

exports.Checker = class Checker extends state.State

    init: ->
        super()
        @expected = []

    expect: (event, cb)->
        @expected.push event
        @save cb

    onState: (event, cb)->
        console.log "======================================================="
        if not @expected.length or @expected[0] != event.state
            console.log "Unexpected [" + event.state + "] " + event.message + " (" + event.id + ")"
            console.log "Expect: ", @expected[0]
            console.trace()
            process.exit(1)
            
            return cb(new Error("Unexpected event:" + JSON.stringify(event)))
        console.log "Expected [" + event.state + "] " + event.message + " (" + event.id + ")"
        console.log "======================================================="
        @expected = @expected[1...]
        @save cb
