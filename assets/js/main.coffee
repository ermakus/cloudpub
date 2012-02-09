#
# Form validation with help of jquery.validate plugin
#

# Disqus
loadDisqus = ->
    disqus_shortname='cloudpub'
    s = document.createElement('script')
    s.async = true
    s.type = 'text/javascript'
    s.src = 'http://' + disqus_shortname + '.disqus.com/embed.js'
    (document.getElementsByTagName('HEAD')[0] || document.getElementsByTagName('BODY')[0]).appendChild(s)

$.validator.addMethod('regexp', ((value, element, regexp) -> @optional(element) or (new RegExp(regexp)).test(value)) , "Invalid symbol")

$.validator.setDefaults
    errorElement: 'span'
    errorClass: 'help-inline'
    highlight: (element, errorClass, validClass) ->
        $(element).parent().parent().addClass('error')
    unhighlight: (element, errorClass, validClass) ->
        $(element).parent().parent().removeClass('error')

# Domain validation
DOMAIN_REGEX = /^(?=.{1,255}$)[0-9A-Za-z](?:(?:[0-9A-Za-z]|\b-){0,61}[0-9A-Za-z])?(?:\.[0-9A-Za-z](?:(?:[0-9A-Za-z]|\b-){0,61}[0-9A-Za-z])?)*\.?$/

$.validator.addMethod 'domain', (value, elem) ->
    $.domain = {valid:false, error:'Invalid domain name',help:'Type correct domain name'}
    if DOMAIN_REGEX.test(value)
        $.ajax
            url:'/resolve/' + value
            async: false
            success: (data) -> $.domain = data
    # Also show separate help message
    $(elem).parent().find('.help-block').html $.domain.help
    $.domain.valid
, -> $.domain.error

#
# Create template renderer by name
#
window.TEMPLATE = TEMPLATE = (name) ->
    text = $(".#{name}-template").html()
    if text
        _.template text.replace(/&amp;/g, "&").replace(/&gt;/g, ">").replace(/&lt;/g, "<").replace(/&quot;/g, "&")
    else
        null

#
# Class to reload DOM element from $path
#
window.Listing = class Listing

    # node = selector or dom node
    # entity = name of item
    constructor: (@node, @entity, template)->
        @path = '/api/' + @entity
        @view = TEMPLATE(template or 'list')
        @timeout = 15000
        @timer = null
        @reload()

    hookCommands: ->
        self = @
        $(@node).find('.command').bind 'click', ->
            id = $(this).attr('data-id')
            command = $(this).attr('data-command')
            handler = new CommandHandler(self.entity, command, self.items[id], (err) -> self.reload() )
            handler.show()

    # Render template
    render: ->
        # Render template to control node
        html = @view( items:@items )
        $(@node).html html
        $(@node).tablesorter()
        @hookCommands()

    # Reload data
    reload: =>
        $.get @path, (data)=>
            @items = {}
            for item in data
                @items[ item.id ] = item
            @render()

    # Start auto-refreshing
    startUpdate: ->
        # Connect websocket if available
        if io?
            @socket = io.connect()
            @socket.on 'message', (data) =>
                styles =
                    up: 'success'
                    error: 'error'
                    down: 'warning'
                    maintain: 'info'
                style = styles[data.state] or 'warning'
                alert data.message, style
                # Push event to google analytics
                if _gaq then _gaq.push(['_trackEvent', data.state, data.message])
                setTimeout( (=> @reload()), 500)

    # Stop auto-refreshing
    stopUpdate: ->
        @socket and @socket.disconnect()

# Helper to execute command on server
window.CommandHandler = class CommandHandler

    # Construct command handler
    # entity = item name
    # command = command name
    # item = item JSON object
    constructor: (@entity, @command, @item, cb) ->
        # Get dialog for command
        template = TEMPLATE command
        if template
            # Render template
            @dlg = $(template(item:@item))
            @dlg.data 'item', @item
            # Bind execute button
            @dlg.find('.execute').bind 'click', => @execute( cb )
            # Remove element after hide
            @dlg.bind 'hidden', => @dlg.remove()
        else
            @dlg = $('<h1>No template</h1>')

    # Show command dialog
    show: ->
        # Validate form before show
        # @validate()
        # Show dialog
        @dlg.modal
            backdrop: true
            keyboard: true
            show: true

    # Hide and remove dialog
    hide: ->
        @dlg.modal('hide')

    # Validate form if available
    validate: ->
        form = @dlg.find('form')
        return true if not form
        validator = form.validate()
        return true if not validator
        validator.form()
 
    execute: (cb) ->
        # Validate form on click
        return if not @validate()
        
        # Set button to Loading... state
        button = $('.execute')
        button.button('loading')
        button.unbind 'click'

        # Func. to hide dialog
        hideDialog = =>
            @hide()
            cb and cb( null )

        form = @dlg.find('form')
        if form.length
            params = form.serializeArray()
        else
            params = []

        params.push {name:'id', value: @item.id}
        params.push {name:'command', value: @command}

        # Execute command on server and close dialog
        $.post "/api/#{@entity}/#{@item.id}", params, (res) =>
            # res is item JSON
            hideDialog()
        .error hideDialog

#
# Messages and alerts (override system alert)
#
window.message = (msg) ->
    alert msg, 'success'

window.error = (err) ->
    $('.modal').modal('hide')
    alert err, 'error'

window.sysalert = window.alert
window.alert = (msg, classes) ->
    if not msg
        msg = "null"
    container = $('.alerts')
    if typeof(msg) != 'string'
        msg = msg.statusText or JSON.stringify msg

    if not container
        sysalert msg
    else
        if msg.indexOf('\n') >= 0
            msg = '<pre>' + msg + '</pre>'
        msg = $("<div class='alert-message fade in #{classes}'><a href='#' class='close'>×</a><p>#{msg}</p></div>")
        # Assign and check, not equal
        msgs = $('.alerts .alert-message:last')
        if msgs.length
            #msg.insertAfter msgs
            msgs.replaceWith msg
        else
            msg.prependTo container
        msg.alert()
        if classes != 'error'
            setTimeout (-> msg.find('.close').click() ), 10000




#
# Initialization to run on all pages
#
$ ->
    # Catch-all ajax error handler
    $('body').ajaxError (ev, req, settings) ->
        if req.responseText
            error req.responseText
        else
            if req.status
                error req.statusText
            else
                error "Connection error"

    # Navidagtion highlighting
    $('#nav li').each ->
        href = $(this).children(':first-child').attr('href')
        if window.location.pathname == href
            $(this).addClass('active')
