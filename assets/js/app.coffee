#
# Form validation with help of jquery.validate plugin
#

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

# Validate form $name, show errors and reuturn state
window.validate_form = (name) ->
    form = $('#' + name + '-form')
    return true if not form
    validator = form.validate()
    return true if not validator
    validator.form()

#
# Class to reload DOM element from $path
#
window.Updater = class Updater

    constructor: (@node, @path, @timeout) ->
        @timeout ?= 15000
        @timer = null

    reload: =>
        $(@node).load @path

    startUpdate: ->
        @timer = setInterval @reload, @timeout

    stopUpdate: ->
        clearInterval @timer
        @timer = null

#
# Listing control and commands dialog manager
#
window.Listing = class Listing extends Updater

    # node = selector of dom node
    # listPath = handler for collection
    # actionPath = handler for collection item
    constructor: (node, listPath, @actionPath )->
        super(node, '/' + listPath + '?type=inline')
        $('table').tablesorter()

        listing = @
        $('.command').live 'click', ->
            el = $(this)
            listing.id = el.attr('data-id')
            listing.command = el.attr('data-command')
            
            #listing.fillDialog listing.command, listing.id
            
            # TODO: Remove it from here
            domain = el.attr('data-domain')
            $('input[name=domain]').val domain

            listing.dialog listing.command, listing.id
        
        $('.execute').live 'click', ->
            listing.execute listing.command, listing.id

    execute: (command, id) ->
        button = $('.execute')
        # Validate form on click
        return if not validate_form( command )

        # Button Loading... state
        button.button('loading')
        button.unbind 'click'

        # Func. to hide dialog
        hide_dialog = =>
            button.button('reset')
            @dlg.modal('hide')
            @dlg = undefined
            @reload()

        form = $('#' + command + '-form')
        if form.length
            params = form.serializeArray()
        else
            params = []

        params.push {name:'id', value: id}

        # Execute command on server and close dialog
        $.post "/#{@actionPath}/#{command}", params, (res) ->
            message res
            hide_dialog()
        .error hide_dialog


    dialog: (command, id) ->
        # Validate form first
        validate_form command
    
        # Get dialog for command
        @dlg = $('#' + command + '-dialog')
        
        @dlg.data 'command', command
        @dlg.data 'id', id

        # Show dialog
        @dlg.modal
            backdrop: true
            keyboard: true
            show: true

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
    container = $('#body')
    if typeof(msg) != 'string'
        msg = msg.statusText or JSON.stringify msg

    if not container
        sysalert msg
    else
        msg = $("<div class='alert-message fade in #{classes}'><a href='#' class='close'>×</a><p>#{msg}</p></div>")
        container.prepend msg
        msg.alert()
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
