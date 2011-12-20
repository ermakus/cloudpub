require('coffee-script');
var app = require('./main');

app.init( function(err, server) {
    if(err) console.log(err); else server.listen( process.argv[2] || 3000 );
});
