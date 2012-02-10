$ ->
    listing = new Listing('.page', 'service')
    listing.startUpdate()

    # Install new app handler
    $('.launch-new').click ->
        # App defaults
        item =
            id: 'new'
            port: 8081
            domain: 'localhost'

        handler = new CommandHandler( 'service', 'launch', item, (err)-> listing.reload())
        handler.show()

    # On startup modal dialog
    $('.launch').live 'shown', ->
        instances = new Listing('#items', 'instance', 'instances')

        # Public checkbox and domian input logic
        domain = $('input[name=domain]')
        public = $('#public')
        domain.attr('data-domain',domain.val())

        # Checkbox event handler
        public_checkbox_handler = ->
            if not $(this).is(':checked')
                domain.attr('data-domain',domain.val())
                domain.val('localhost').addClass('uneditable-input').attr('readonly', true)
            else
                domain.val(domain.attr('data-domain')).removeClass('uneditable-input').attr('readonly', false)
        public.change( public_checkbox_handler )

        # Set default checkbox state
        if domain.val() != 'localhost'
            public.attr('checked',true)
        public.change()

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
