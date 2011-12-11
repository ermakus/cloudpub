var pamlib = require('../pam.node');
var pam = new pamlib.PAM();

// This should output false because (clearly) your username is not myusername
// and your password is mypassword. Change it and it should work!

// PAM service name. On Fedora 15, standard system auth service name is system-auth.
// Change accordingly or write your own.
var service = "system-auth";
var username = "anton";
var password = "re've'679";

pam.authenticate(service, username, password, function(result) {
	console.log("Username: " + username + ", password: " + password + ", result: " + result);
});


console.log("This will get printed first");
