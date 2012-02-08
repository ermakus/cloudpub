CloudPub.us source code
=======================

CloudPub currently is on very early development stage, and some features is not tested or complete yet.

Install
-------

> git clone git@github.com:ermakus/cloudpub.git

or

> npm install -g cloudpub


By default cloudpub use plain JSON files to store cluster state.

Start
-----
You need to have default ssh keypair for adding other servers.
So, please run ssh-keygen first.

> node server.js

or

> npm start -g cloudpub

then open web interface on http://localhost:4000

License
-------

Please see LICENSE file.
