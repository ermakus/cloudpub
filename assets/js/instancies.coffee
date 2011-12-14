$ ->
    $('.cloud').click ->
        if $(this).val() == 'ec2'
            $('.custom').hide()
            $('.custom-input').removeClass 'required'
        else
            $('.custom').show()
            $('.custom-input').addClass 'required'
    listing = new Listing('tbody', 'instancies', 'instance')
    listing.startUpdate()
