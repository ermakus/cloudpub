require('coffee-script');
main = require('./main')
exports.log  = main.log
exports.init = main.init
exports.stop = main.stop
exports.cloudfu = require('./cloudfu');
exports.service = require('./service');
