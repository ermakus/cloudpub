#### Nginx proxy module

##### Startup commands
exports.startup = -> [
    {
        entity:  "shell"
        message: "Configure proxy"
        state:   "maintain"
        context:
            id: @id
            home: @home
            port: @port
            domain: @domain
            default: true
            services: null
        command: ['domain','enable']
        success:
            state:'maintain'
            message: 'Proxy configured'
    },
    {
        entity:  "shell"
        message: "Start Proxy"
        state:   "maintain"
        command: ["daemon", "start", @id, "./sbin/nginx", "-c", "#{@home}/conf/nginx.conf" ]
        success:
            state:'up'
            message: 'Online'
    }
]

##### Shutdown commands
exports.shutdown = -> {
    entity:  "shell"
    message: "Stop Proxy"
    state:   "maintain"
    context:
        id: @instance
    command:["daemon", "stop", @id]
    success:
        state:   'down'
        message: 'Offline'
}


##### Compile and install nginx
exports.install = -> {
    entity:  'shell'
    message: "Compile proxy"
    state:   "maintain"
    home: @home
    command:["install-proxy", @home]
    success:
        state: "maintain"
        message: "Proxy installed"
}


##### Uninstall nginx
exports.uninstall = -> {
    state: 'maintain'
    message: 'Uninstall proxy'
    entity:  'shell'
    command:['echo','params']
    success:
        state:'down'
        message: 'Proxy uninstalled'
}

