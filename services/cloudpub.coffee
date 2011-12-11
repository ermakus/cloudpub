SERVICE = exports
ENV     = require '../env'

# Service display name
SERVICE.name = 'CloudPub master node'

# State: DOWN, MANTAINING or UP
SERVICE.state = 'down'

# Service source (GIT repo)
SERVICE.source = '/home/anton/Projects/cloudpub'

# Return service status for given user account
SERVICE.info = (acc, cb)->
    # Default service info
    info =
        sid:exports.sid
        name:SERVICE.name
        state:SERVICE.state
        domain:"#{acc.uid}-#{SERVICE.sid}.cloudpub.us"

    # Fire callback (if set) with null error
    cb and cb(null, info)

# Start service
SERVICE.start = (acc, params, cb)->
    SERVICE.state = 'maintain'
    ENV.install acc, SERVICE.sid, SERVICE.source, (err)->
        return cb and cb(err) if err
        ENV.start acc, SERVICE.sid, (err)->
            return cb and cb(err) if err
            SERVICE.state = 'up'
            cb and cb(err)

# Stop service
SERVICE.stop = (acc, params, cb)->
    SERVICE.state = 'maintain'
    ENV.uninstall acc, SERVICE.sid, (err)->
        return cb and cb(err) if err
        ENV.stop acc, SERVICE.sid, (err)->
            return cb and cb(err) if err
            SERVICE.state = 'down'
            cb and cb(err)
