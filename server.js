require('coffee-script');
var app = require('./main');
var nconf = require('nconf');

app.init( function(err, server) {
    if(err) console.log(err); else server.listen( nconf.get('listen') || 3000 );
});
