logger = require './logger'
uuid  = require './uuid'
fs    = require 'fs'
nconf = require 'nconf'

# Take settings from everywhere
nconf.argv()
nconf.env()

# Unique ID of instance or service
@ID = nconf.get('id') or "MASTER" #uuid.v1()

# Domain of service
@DOMAIN = DOMAIN = nconf.get('domain') or 'localhost'

# Port to listen
@PORT   = PORT   = nconf.get('port') or 4000

# Master node domain
@MASTER = nconf.get('master') or undefined

# Master node port
@MASTER_PORT = nconf.get('master-port') or PORT

# Current system user
@USER = process.env.USER or "root"

# Current user home
@HOME = process.env.HOME or "/root"

# Public key file path
@PUBLIC_KEY_FILE = "#{@HOME}/.ssh/id_rsa.pub"

# Public key file
try
    @PUBLIC_KEY = fs.readFileSync( @PUBLIC_KEY_FILE )
catch e
    @PUBLIC_KEY = "Not found - please run ssh-keygen"

# Private key file
@PRIVATE_KEY_FILE = "#{@HOME}/.ssh/id_rsa"

# GC interval, ms
@GC_INTERVAL = nconf.get('gc-interval') or 60000

# Init logger
@log = log = logger.create()
log.level = nconf.get('log-level') or 2

@SNAPSHOT_FILE= nconf.get('snapshot') or __dirname + '/snapshot.json'

nconf.file { file:@SNAPSHOT_FILE }

# Print config if debug mode
if nconf.get('debug')
    log.level = 0
    for key of exports
        log.debug "[bold]#{key}[/bold]:\t\t#{@[key]}"
