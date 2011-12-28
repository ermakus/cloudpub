$ ->
    $('.create').ajaxForm ->
        $('input.url').val('')
        alert "Application submitted"

    $('.url').popover {
        title: -> "A source is"
        content: -> $('.popover').html()
        html: true
        placement:'left'
    }

    listing = new Listing('.page', 'app')
    listing.startUpdate()
    $('.startup').live 'shown', ->
        instances = new Listing('#items', 'instance', 'instances')
