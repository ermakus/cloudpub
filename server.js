require('coffee-script');
var settings = require('./settings');
var main = require('./main');

main.init( function(err, server) {
    if(err) {
        console.log(err)
    } else {
        server.on('error', function(err) {
            account.log.error( "Fatal error: " + err.message );
            process.exit(1);
        });
        main.log.info("Server started on " + settings.DOMAIN + ":" + settings.PORT );
        server.listen( settings.PORT );
    }
});
