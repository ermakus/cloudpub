#
# Custom cloud manager (SSH nodes)
#
spawn = require('child_process').spawn

SSH_PRIVATE_KEY='/home/anton/.ssh/id_rsa'

exports.install = (params, cb) ->
    @user = params.user
    @address = params.address
    @id = "c-#{@address}"
    ch = spawn "ssh", ['-i', SSH_PRIVATE_KEY, '-o', 'StrictHostKeyChecking no', '-o', 'BatchMode yes', @user + '@' + @address, 'ls' ]
    ch.stdout.on 'data', (data) -> console.log data.toString()
    ch.stderr.on 'data', (data) -> console.log data.toString()
    ch.on 'exit', (code) =>
        console.log "SSH exit with error: #{code}"
        if code == 0
            state = 'up'
        else
            state = 'down'
        @setState state, (err)->
            if err
                console.log "Status save error #{err}"
    console.log ch
    cb and cb( null )

exports.uninstall = (params, cb) ->
    console.log "Uninstall SSH node: #{@id}"
    @clear (err) ->
        cb and cb( err )

