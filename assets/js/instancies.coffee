validate_form = (name) ->
    form = $('#' + name + '-form')
    return true if not form
    validator = form.validate()
    return true if not validator
    validator.form()

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


            form = $('#' + command + '-form')
            if form.length
                params = form.serializeArray()
            else
                params = []

            params.push {name:'sid', value: sid}

            # Execute command on server and close dialog
            $.post "/service/#{command}", params, (res) ->
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
    $('.command, .new').live 'click', show_dialog
