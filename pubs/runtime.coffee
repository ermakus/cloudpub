#### NodeJs runtime module

##### Install commands
exports.install = -> [
    # Upload install scripts
    {
                entity: 'sync'
                package: "shell"
                message: "Sync service files"
                state:   "maintain"
                home:    "/"
                source: __dirname + "/../bin"
                target: "#{@home}/" # Slash important!
                success:
                    state:'maintain'
                    message:'Done'
    },
    # Download and compile runtime
    {
                entity:  'shell'
                message: "Compile node runtime"
                state:   "maintain"
                command:["install-node", @home]
                success:
                    state:'up'
                    message: 'Runtime compiled'
    }
]

##### Uninstall commands
exports.uninstall = -> {
    state: 'maintain'
    message: 'Uninstall runtime'
    entity:  'shell'
    command:['rm','-rf', @home]
    success:
        state:'down'
        message: 'Runtime uninstalled'
}
