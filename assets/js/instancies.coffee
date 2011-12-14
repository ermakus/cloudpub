init_clipboard = ->
    # Init copy-to-clipboard flash kostyl
    clip = new ZeroClipboard.Client()
    clip.glue "clip-button", 'clip-container'
    clip.setText $('#pubkey').val()
    clip.addEventListener 'load', (client)->
        clip.setHandCursor(true)
    clip.addEventListener 'complete', (client, text)->
        alert "Public key copied to clipboard"

$ ->
    init_clipboard()

    $('.cloud').click ->
        if $(this).val() == 'ec2'
            $('.custom').hide()
            $('.custom-input').removeClass 'required'
        else
            $('.custom').show()
            $('.custom-input').addClass 'required'

    $('#start-dialog').bind 'show', ->
        if $(this).data('id') != 'new'
            $('.cloudtype').hide()
            $('.address').attr 'readonly', true
        else
            $('.address').attr 'readonly', false
            $('.cloudtype').show()
    

    listing = new Listing('table', 'instancies', 'instance')
    listing.startUpdate()
