#
# npm module
#

##### Startup commands
exports.startup = -> [
    {
        entity:  "shell"
        message: "Start Service"
        state:   "maintain"
        command: ["daemon", "-b", "#{@home}/lib/node_modules/#{@name}/",
                  "start", @id, "#{@home}/lib/node_modules/#{@name}/server", '--port=' + @port, '--domain=' + @domain ]
        success:
            state:'up'
            message: 'Online'
    },
    {
        entity:  "shell"
        message: "Configure proxy"
        state:   "maintain"
        context:
            id: @id
            home: @home
            port: @port
            domain: @domain
            default: false
            services: "server localhost:#{@port};"
        command: ['domain','enable']
        success:
            state:'maintain'
            message: 'Proxy configured'
    }
]

##### Shutdown commands
exports.shutdown = -> {
    entity:  "shell"
    message: "Stop Service"
    state:   "maintain"
    command:["daemon", "stop", @id]
    success:
        state:   'down'
        message: 'Offline'
}

exports.install = -> {
    entity: 'shell'
    message: "Install Service"
    state:   "maintain"
    command:["npm","-g","install", @name]
    success:
        state:'maintain'
        message: 'Cloudpub Installed'
}

exports.uninstall = -> {
    state: 'maintain'
    message: "Uninstall Cloudpub"
    entity:  'shell'
    command:["npm","-g","uninstall", @name]
    success:
        state:'down'
        message: 'Cloudpub Uninstalled'
}

