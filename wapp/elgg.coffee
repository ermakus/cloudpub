SERVICE = exports

SERVICE.name = 'Elgg Social Network'

SERVICE.source = '/home/anton/Projects/elgg-1.8.1'

SERVICE.start = (params, cb) ->
    console.log "Elgg Starting: " + JSON.stringify params
    @def_start( params, cb )

