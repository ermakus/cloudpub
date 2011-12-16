#
# Custom cloud manager (SSH nodes)
#
exports.install = (params, cb) ->
    @worker 'scp', (err,worker) =>
        return cb and cb(err) if err
        worker.user = @user
        worker.address = @address
        worker.source = '/home/anton/Projects/cloudpub'
        worker.target = '~/cloudpub'
        worker.start cb

exports.uninstall = (params, cb) ->
    target = '~/cloudpub'
    @worker 'ssh', (err,worker) =>
        return cb and cb(err) if err
        worker.user = @user
        worker.address = @address
        worker.command = ['rm','-rf', target]
        worker.on 'success', (err, worker) =>
            return cb and cb( err ) if err
            @clear (err) ->
                cb and cb( err )
        worker.start cb
