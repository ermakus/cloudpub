logger = require './logger'
uuid  = require './uuid'
fs    = require 'fs'
nconf = require 'nconf'

# Take settings from everywhere
nconf.argv()
nconf.env()

# Init logger
exports.log = log = logger.create()
log.level = nconf.get('log-level') or 3

# Monkey patch for separate test context
if process.argv.join(' ').indexOf('kya test') > 0
    console.log "In test mode"
    file = __dirname + '/test-snapshot.json'
    nconf.file {file}
else
    nconf.file
        file: __dirname + '/prod-snapshot.json'

# Unique ID of instance or service
exports.ID = nconf.get('id') or uuid.v1()

# Domain of service
exports.DOMAIN = DOMAIN = nconf.get('domain') or 'localhost'

# Port to listen
exports.PORT   = PORT   = nconf.get('port') or 4000

# Master node domain
exports.MASTER = nconf.get('master') or undefined

# Master node port
exports.MASTER_PORT = nconf.get('master-port') or PORT

# Current system user
exports.USER = process.env.USER or "root"

# Current user home
exports.HOME = process.env.HOME or "/root"

# Public key file path
exports.PUBLIC_KEY_FILE = "#{exports.HOME}/.ssh/id_rsa.pub"

# Public key file
try
    exports.PUBLIC_KEY = fs.readFileSync( exports.PUBLIC_KEY_FILE )
catch e
    exports.PUBLIC_KEY = "Not found - please run ssh-keygen"

# Private key file
exports.PRIVATE_KEY_FILE = "#{exports.HOME}/.ssh/id_rsa"

# Print config if debug mode
if nconf.get('debug')
    log.level = 0
    for key of exports
        log.debug "[bold]#{key}[/bold]:\t#{exports[key]}"
