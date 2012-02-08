#
# npm module
#

##### Startup commands
exports.startup = -> [
    {
        entity:  "shell"
        message: "Start Service"
        state:   "maintain"
        context:
            id:@id
            home:@home
            address:@address
        command: ["daemon"
                  "-p"
                  "-b"
                  "#{@home}/lib/node_modules/#{@name}/"
                  "start"
                  @id
                  "#{@home}/lib/node_modules/#{@name}/server"
                  "--home=" + @home
                  "--port=" + @port
                  "--domain=" + @domain
                  "--address=" + @address]
        success:
            state:'up'
            message: 'Started'
    },
    {
        entity:  "shell"
        message: "Attach to proxy"
        state:   "maintain"
        context:
            id: @proxy
            home: @home
            port: @proxy_port
            domain: @domain
            default: false
            services: "server #{@address}:#{@port};"
        command: ['domain','enable']
        success:
            state:'maintain'
            message: 'Online'
    }
]

##### Shutdown commands
exports.shutdown = -> [
    {
        entity:  "shell"
        message: "Detach from proxy"
        state:   "maintain"
        context:
            id: @proxy
            home: @home
            port: @port
            domain: @domain
            default: false
            services: "server #{@address}:#{@port};"
        command: ['domain','disable']
        success:
            state:'maintain'
            message: 'Offline'
    },
    {
        entity:  "shell"
        message: "Stop Service"
        state:   "maintain"
        command:["daemon", "stop", @id]
        success:
            state:   'down'
            message: 'Stopped'
    }
]

exports.install = -> {
    entity: 'shell'
    message: "Install Service"
    state:   "maintain"
    command:["npm","-g","install", @name]
    success:
        state:'maintain'
        message: 'Installed'
}

exports.uninstall = -> {
    state: 'maintain'
    message: "Uninstall service"
    entity:  'shell'
    command:["npm","-g","uninstall", @name]
    success:
        state:'down'
        message: 'Uninstalled'
}

