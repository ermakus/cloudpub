DOMAIN_REGEX = /^(?=.{1,255}$)[0-9A-Za-z](?:(?:[0-9A-Za-z]|\b-){0,61}[0-9A-Za-z])?(?:\.[0-9A-Za-z](?:(?:[0-9A-Za-z]|\b-){0,61}[0-9A-Za-z])?)*\.?$/

$.validator.addMethod 'domain', (value, elem) ->
    $.domain = {valid:false, error:'Invalid domain name',help:'Type correct domain name'}
    if DOMAIN_REGEX.test(value)
        $.ajax
            url:'/resolve/' + value
            async: false
            success: (data) -> $.domain = data
    $(elem).parent().find('.help-block').html $.domain.help
    $.domain.valid
, -> $.domain.error

validate_form = (name) ->
    form = $('#' + name + '-form')
    return true if not form
    validator = form.validate()
    return true if not validator
    validator.form()

timer = null

update_services = ->
    $('tbody').load '/services?naked=true'

update_start = ->
    timer = setInterval update_services, 15000

update_stop = ->
    clearInterval timer


show_dialog = ->
    sid = $(this).attr('data-sid')
    command = $(this).attr('data-command')
    domain = $(this).attr('data-domain')
    $('input[name=domain]').val domain
    validate_form command
    
    # Get dialog for command
    dialog = $('#' + command + '-dialog')

    # Rebind show event handlers
    dialog.unbind('show').bind 'show', ->
        # Hook on execute button
        button = $('.execute')
        button.unbind('click').bind 'click', ->
            # Validate form on click
            return if not validate_form( command )

            # Button Loading... state
            button.button('loading')
            button.unbind 'click'

            # Func. to hide dialog
            hide_dialog = ->
                button.button('reset')
                dialog.modal('hide')
                update_services()

            # Execute command on server and close dialog
            $.get "/service/#{command}", {sid}, (res) ->
                message "Command #{command} executed on service #{sid}"
                hide_dialog()
            .error hide_dialog

    # Show modal dialog
    dialog.modal
        backdrop: true
        keyboard: true
        show: true

$ ->
    $('table').tablesorter()
    $('.command').live 'click', show_dialog
    update_start()
