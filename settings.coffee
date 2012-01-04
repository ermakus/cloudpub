fs = require 'fs'
nconf = require 'nconf'
nconf.argv()

# Domain of service
exports.DOMAIN = DOMAIN = nconf.get('domain') or 'localhost'
# Port to listen
exports.PORT   = PORT   = nconf.get('listen') or 4000
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

nconf.defaults {
    listen:3000
    test:false
}

if not nconf.get('test')
    nconf.file
        file: __dirname + '/snapshot.json'
else
    nconf.file
        file: __dirname + '/test-snapshot.json'
