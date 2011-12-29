require('coffee-script');
var app = require('./main');
var account = require('./account');

app.init( function(err, server) {
    if(err) {
        console.log(err)
    }
    else {
        account.log.info("Server started on " + account.DOMAIN + ":" + account.PORT );
        server.listen( account.PORT );
    }
});
