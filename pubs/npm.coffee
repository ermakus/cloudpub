#
# npm module
#

##### Startup command
exports.startup = ->
    # Start daemon
    start = {
        entity:  "shell"
        message: "Start Service"
        state:   "maintain"
        context:
            id:@id
            home:@home
            host:@host
            domain:@domain
        command: ["#{@home}/bin/forever-daemon"
                  "start"
                  @id
                  "#{@home}/lib/node_modules/#{@name}/server"
                  "--home=" + @home
                  "--port=" + @port
                  "--domain=" + @domain
                  "--host=" + @host]
        success:
            state:'up'
            message: 'Started'
    }
    # Attach to proxy
    attach = {
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
    # We only attach to proxy if public domain set
    if @domain == 'localhost'
        return [start]
    else
        return [start, attach]

##### Shutdown command
exports.shutdown = ->
    # Detach from proxy
    detach = {
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
    }
    # Stop daemon
    stop = {
        entity:  "shell"
        message: "Stop Service"
        state:   "maintain"
        command:["#{@home}/bin/forever-daemon", "stop", @id]
        success:
            state:   'down'
            message: 'Stopped'
    }
    # detach only if public domain
    if @domain == 'localhost'
        return [stop]
    else
        return [detach, stop]

# Install npm package
exports.install = -> {
    entity: 'shell'
    message: "Install Service"
    state:   "maintain"
    command:["npm","-g","install", @source or @name]
    success:
        state:'maintain'
        message: 'Installed'
}

# Uninstall npm package
exports.uninstall = -> {
    state: 'maintain'
    message: "Uninstall service"
    entity:  'shell'
    command:["npm","-g","uninstall", @name]
    success:
        state:'down'
        message: 'Uninstalled'
}

