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

# Network interface to run
@HOST= nconf.get('host') or '127.0.0.1'

# Master node domain
@MASTER = nconf.get('master') or undefined

# Master node port
@MASTER_PORT = nconf.get('master-port') or PORT

# Current system user
@USER = process.env.USER or "root"

# Current user home
@HOME = process.env.HOME or "/root"

# Dry run - do not execute shell commands
@DRY_RUN = nconf.get('dry-run') or false

# Debug mode
@DEBUG = nconf.get('debug') or false

# Session GC interval, ms
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
