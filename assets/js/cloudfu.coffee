$ ->
    listing = new Listing('.page', 'cloudfu')
    listing.startUpdate()
    
    instances = new Listing('#instances', 'instance', 'instances')

    # Install new app handler
    $('#fu').keypress (e)->
        if e.which == 13 then $('#kya').click()

    $('#kya').click ->
        command = $('#fu').val()
        instance = $('input[name=instance]:checked').val()

        $.post "/kya", {command, instance}, (done)->
            $('#fu').val('')
            listing.reload()
