$ ->
    $('.create').ajaxForm ->
        $('input.url').val('')
        alert "Application submitted"

    listing = new Listing('.page', 'app')
    listing.startUpdate()
    $('.startup').live 'shown', ->
        instances = new Listing('#items', 'instance', 'instances')
