init_clipboard = ->
    # Init copy-to-clipboard flash kostyl
    clip = new ZeroClipboard.Client()
    clip.glue "clip-button", 'clip-container'
    clip.setText $('#pubkey').val()
    clip.addEventListener 'load', (client)->
        clip.setHandCursor(true)
    clip.addEventListener 'complete', (client, text)->
        message "Public key copied to clipboard"


init_cloud_type = (type)->
    if type == 'ec2'
        $('.custom').hide()
        $('.custom-input').removeClass 'required'
    else
        $('.custom').show()
        $('.custom-input').addClass 'required'

$ ->
    # Switch start server view mode
    $('.cloud').live 'click', ->
        init_cloud_type $(this).val()

    $('.start').live 'shown', ->
        item = $(this).data('item')
        return if not item
        init_cloud_type item.cloud
        if item.id != 'new'
            $('.cloudtype').hide()
            $('.address').attr 'readonly', true
        else
            $('.address').attr 'readonly', false
            $('.cloudtype').show()
        init_clipboard()
    
    # Show listing
    listing = new Listing('.page', 'instances', 'instance')
    listing.startUpdate()

    # Start new server handler
    $('.start-new').click ->
        # Server defaults
        item =
            id: 'new'
            cloud: 'ssh'
            address: '127.0.0.1'
            user: 'root'

        handler = new CommandHandler( 'instance', 'start', item, (err)-> listing.reload())
        handler.show()


