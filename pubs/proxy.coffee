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
        command: ["#{@home}/bin/domain", "enable" ]
        success:
            state:'maintain'
            message: 'Proxy configured'
    },
    {
        entity:  "shell"
        message: "Start Proxy"
        state:   "maintain"
        command: ["#{@home}/bin/forever-daemon", "start", "#{@home}/sbin/nginx", "-c", "#{@home}/conf/nginx.conf" ]
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
    command:["#{@home}/bin/forever-daemon", "stop", @id]
    success:
        state:   'down'
        message: 'Offline'
}


##### Compile and install nginx
exports.install = -> {
    entity:  'shell'
    message: "Compile proxy"
    state:   "maintain"
    command:["#{@home}/bin/install-proxy", @home]
    success:
        state: "maintain"
        message: "Proxy installed"
}


##### Uninstall nginx
exports.uninstall = -> {
    state: 'maintain'
    message: 'Uninstall proxy'
    entity:  'shell'
    command:['echo','Not implemented']
    success:
        state:'down'
        message: 'Proxy uninstalled'
}

