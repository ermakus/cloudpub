#
# Custom cloud manager (SSH nodes)
#
exports.install = (params, cb) ->
    console.log "Installing to server", @
    source = '/home/anton/Projects/cloudpub'
    target = '~/cloudpub'
    worker = @createWorker()
    # Sync woker and server state
    worker.on 'state', (state,message) =>
        console.log "Worker: #{state}:#{message}", @
        @setState state, message
    worker.scp source, target, cb

exports.uninstall = (params, cb) ->
    console.log "Uninstalling from server", @
    target = '~/cloudpub'
    worker = @createWorker()
    # Sync woker and server state
    worker.on 'state', (state, message) =>
        console.log "Worker: #{state}:#{message}", @
        @setState state, message
    worker.ssh ['rm','-rf', target], (err) =>
        return cb and cb( err ) if err
        @clear (err) ->
            cb and cb( err )

