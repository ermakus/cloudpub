# logger = require('logger').create()
# logger.info("blah")
# => [2011-3-3T20:24:4.810 info (5021)] blah
# logger.debug("boom")
# =>
# logger.level = Logger.levels.debug
# logger.debug(function() { return "booom" })
# => [2011-3-3T20:24:4.810 error (5021)] booom

terminal = require "terminal"

class Logger
  constructor: (options) ->
    @options = options or {}
    @level   = @options.level or Logger.levels.info
    for level, num of Logger.levels
      Logger.define @, level

  add: (level, args) ->

    if @level > (Logger.levels[level] or 5)
      return

    message = ""
    for arg in args
        if typeof(arg) == 'string'
            message += arg
        else
            message += JSON.stringify(arg)
        message += " "
 
    message = message.replace(/[\r\n]$/, "")

    @write(
      timestamp: new Date
      severity:  level
      message:   message
      pid:       process.pid
    )

  # Overwrite this to write to a file, a db, etc
  write: (options) ->
    console.log @build_message(options)

  build_message: (options) ->
    color = Logger.colors[options.severity]
    if not @options.notime
        timestr =
            "[grey]#{options.timestamp.getUTCFullYear()}" +
            "-#{options.timestamp.getUTCMonth()+1}" +
            "-#{options.timestamp.getUTCDay()}" +
            "T#{options.timestamp.getUTCHours()}" +
            ":#{options.timestamp.getUTCMinutes()}" +
            ":#{options.timestamp.getUTCSeconds()}" +
            "[/grey] "
    else
        timestr = ""

    terminal.stylize( timestr + "[#{color}]#{options.severity}[/#{color}] " + options.message )

Logger.define = (logger, level) ->
  logger[level] = (args...)-> logger.add level, args

Logger.levels =
  debug: 1
  info:  2
  warn:  3
  error: 4
  fatal: 5
  stdout: 6
  stderr: 7

Logger.colors =
  debug: 'grey'
  info:  'white'
  warn:  'yellow'
  error: 'red'
  fatal: 'red'
  stdout: 'blue'
  stderr: 'red'

exports.create = (type, options) ->
  new Logger(options)
