require('coffee-script');
var app = require('./main');
var account = require('./account');

app.init( function(err, server) {
    if(err) {
        console.log(err)
    } else {
        server.on('error', function(err) {
            account.log.error( "Fatal error: " + err.message );
            process.exit(1);
        });
        account.log.info("Server started on " + account.DOMAIN + ":" + account.PORT );
        server.listen( account.PORT );
    }
});
