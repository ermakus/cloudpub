init_clipboard = ->
    if typeof(ZeroClipboard) != 'undefined'
        # Init copy-to-clipboard flash kostyl
        clip = new ZeroClipboard.Client()
        clip.glue "clip-button", 'clip-container'
        clip.setText $('#pubkey').val()
        clip.addEventListener 'load', (client)->
            clip.setHandCursor(true)
        clip.addEventListener 'complete', (client, text)->
            message "Public key copied to clipboard"
    else
        # Trick: see layout header
        error "Session expired"
        window.location.reload()


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

    $('.startup').live 'shown', ->
        item = $(this).data('item')
        return if not item
        init_cloud_type item.entity
        if item.id != 'new'
            $('.cloudtype').hide()
            $('.address').attr 'readonly', true
        else
            $('.address').attr 'readonly', false
            $('.cloudtype').show()
        init_clipboard()

        # Dialog tabs
        $('.tabs').tabs()
        # Help tooltips
        $('a[rel=twipsy]').twipsy()
        $('a[rel=popover]').popover(html:true)
        # Source help
     
    # Show listing
    listing = new Listing('.page', 'instance')
    listing.startUpdate()

    # Start new server handler
    $('.startup-new').click ->
        # Server defaults
        item =
            id: 'new'
            cloud: 'ssh'
            address: '127.0.0.1'
            user: 'cloudpub'
            port: '8080'

        handler = new CommandHandler( 'instance', 'startup', item, (err)-> listing.reload())
        handler.show()


