$ ->

    # Install new app handler
    $('.startup-new').click ->
        # App defaults
        item =
            id: 'new'
            domain: 'app.cloudpub.us'

        handler = new CommandHandler( 'app', 'startup', item, (err)-> listing.reload())
        handler.show()

    listing = new Listing('.page', 'app')
    listing.startUpdate()

    # On startup modal dialog
    $('.startup').live 'shown', ->
        instances = new Listing('#items', 'instance', 'instances')

        # Server list validation
        $('form.modal-body').validate({
            messages:
                instance: 'At least one server is required'

            errorPlacement: (error, element)->
                if element.attr('name') == 'instance'
                    error.insertBefore $('#items')
                else
                    error.insertAfter element

            highlight: (element, errorClass, validClass)->
                $(element).parent().parent().addClass('error')
                if $(element).attr('name') == 'instance'
                    $('a[href="#servers"]').addClass 'label important'

            unhighlight: (element, errorClass, validClass)->
                $(element).parent().parent().removeClass('error')
                if $(element).attr('name') == 'instance'
                    $('a[href="#servers"]').removeClass 'label important'

        })

        # Dialog tabs
        $('.tabs').tabs()
        # Help tooltips
        $('a[rel=twipsy]').twipsy()
        # Source help
        $('.urlpopover').popover {
            title: -> "A source is"
            content: -> $('.popover').html()
            html: true
            placement:'right'
        }
