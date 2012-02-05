#
# Cloudpub module
#

##### Startup commands
exports.startup = -> [
    {
        entity:  "shell"
        message: "Start Cloudpub"
        state:   "maintain"
        command: ["daemon", "-b", "#{@home}/lib/node_modules/cloudpub/",
                  "start", @id, "#{@home}/lib/node_modules/cloudpub/server", '--port=' + @port ]
        success:
            state:'up'
            message: 'Online'
    }
]

##### Shutdown commands
exports.shutdown = -> {
    entity:  "shell"
    message: "Stop Cloudpub"
    state:   "maintain"
    command:["daemon", "stop", @id]
    success:
        state:   'down'
        message: 'Offline'
}

exports.install = -> {
    entity: 'shell'
    message: "Install Cloudpub"
    state:   "maintain"
    command:["npm","-g","install",__dirname]
    success:
        state:'maintain'
        message: 'Cloudpub Installed'
}

exports.uninstall = -> {
    state: 'maintain'
    message: "Uninstall Cloudpub"
    entity:  'shell'
    command:["npm","-g","uninstall","cloudpub"]
    success:
        state:'down'
        message: 'Cloudpub Uninstalled'
}

