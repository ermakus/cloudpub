$ ->
    listing = new Listing('.page', 'service')
    listing.startUpdate()
    $('.start').live 'shown', ->
        instances = new Listing('#items', 'instance', 'instances')
