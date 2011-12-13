# Configure from validator

$.validator.addMethod('regexp', ((value, element, regexp) -> @optional(element) or (new RegExp(regexp)).test(value)) , "Invalid symbol")

$.validator.setDefaults
    errorElement: 'span'
    errorClass: 'help-inline'
    highlight: (element, errorClass, validClass) ->
        $(element).parent().parent().addClass('error')
    unhighlight: (element, errorClass, validClass) ->
        $(element).parent().parent().removeClass('error')

window.message = (msg) ->
    alert msg, 'success'

window.error = (err) ->
    $('.modal').modal('hide')
    alert err, 'error'

window.sysalert = window.alert
window.alert = (msg, classes) ->
    container = $('#body')
    if typeof(msg) != 'string'
        msg = msg.statusText or JSON.stringify msg

    if not container
        sysalert msg
    else
        msg = $("<div class='alert-message fade in #{classes}'><a href='#' class='close'>×</a><p>#{msg}</p></div>")
        container.prepend msg
        msg.alert()
        setTimeout (-> msg.find('.close').click() ), 10000

# Entry point
$ ->
    # Catch-all ajax error handler
    $('body').ajaxError (ev, req, settings) ->
        if req.responseText
            error req.responseText
        else
            if req.status
                error req.statusText
            else
                error "Connection error"
    $('#nav li').each ->
        href = $(this).children(':first-child').attr('href')
        if window.location.pathname == href
            $(this).addClass('active')
