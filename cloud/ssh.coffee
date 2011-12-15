#
# Custom cloud manager (SSH nodes)
#
spawn = require('child_process').spawn

SSH_PRIVATE_KEY='/home/anton/.ssh/id_rsa'
RUN_TIMEOUT=500

exports.install = (params, cb) ->
    @user = params.user
    @address = params.address
    @id = "c-#{@address}"
   
    source = '/home/anton/Projects/cloudpub'
    target = '~/cloudpub'

    scp     = ["scp", '-r', '-i', SSH_PRIVATE_KEY, '-o', 'StrictHostKeyChecking no', '-o', 'BatchMode yes', source, @user + '@' + @address + ':' + target ]

    command = ['uname','-a']
    ssh     = ["ssh",'-i', SSH_PRIVATE_KEY, '-o', 'StrictHostKeyChecking no', '-o', 'BatchMode yes', '-l', @user, @address ]
    
    run = scp #ssh.concat command

    console.log run.join " "
    stdout = ''
    stderr = ''
    ch = spawn run[0], run[1...]
    timer = setTimeout (=>
        timer = null
        @setState 'maintain', 'Executing...', cb
    ), RUN_TIMEOUT

    ch.stdout.on 'data', (data) ->
        console.log "SHELL: ", data.toString()
        stdout += data.toString()

    ch.stderr.on 'data', (data) ->
        stderr += data.toString()
        console.log "ERROR: ", data.toString()
    
    ch.on 'exit', (code) =>
        callback = undefined
        if timer
            clearTimeout timer
            callback = cb
        if code == 0
            @setState 'up', stdout, callback
        else
            @setState 'error', stderr, ->
                callback and callback( new Error( stderr ) )
     

exports.uninstall = (params, cb) ->
    console.log "Uninstall SSH node: #{@id}"
    @clear (err) ->
        cb and cb( err )

