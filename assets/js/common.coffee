#
# Paginated collection
#

window.PaginatedCollection = class PaginatedCollection extends Backbone.Collection

    constructor: ->
        @page = 1
        @perPage = 50
        @params = {}
        super()

    parse: (resp)->
        @page    = resp.page
        @perPage = resp.perPage
        @total   = resp.total
        resp.models
 
    url: ->
        @params.page = @page
        @params.perPage = @perPage
        return this.baseUrl + '?' + $.param(@params)
  
    pageInfo: ->
        info =
            total: @total
            page: @page
            perPage: @perPage
            pages: Math.ceil(@total / @perPage)
            prev: false
            next: false

        max = Math.min(@total, @page * @perPage)

        if @total == @pages * @perPage
            max = this.total

        if @page > 1
            info.prev = this.page - 1

        if @page < info.pages
            info.next = this.page + 1

        return info

    appendPage: ->
        if not @pageInfo().next
            return false
        @page += 1
        return this.fetch(add:true)

    nextPage: ->
        if not @pageInfo().next
            return false
        @page += 1
        return this.fetch()

    setPage: (page)->
        @page = page
        return this.fetch()
 
    previousPage: ->
        if not @pageInfo().prev
            return false
        @page -= 1
        return this.fetch()


window.Widget = class Widget

    value: (model, name) ->
        model.escape name

    renderField: (field, model, name)->
        "<td>#{@value(model,name)}</td>"

    renderInput: (field, model, name) ->
        if name == 'id' and not model.isNew() then state = 'disabled' else state = ''
        "<input #{state} id='field-#{name}' name='#{name}' type='#{field.type or 'text'}' value='#{@value(model,name)}'>"

    render: (field, model, name) ->
        html = "<div id='f_#{name}' class='clearfix'><label>#{field.label or name}</label>"
        html += "<div class='input'>" + @renderInput field, model, name
        html += "<span class='help-inline'>#{field.hint or ""}</span></div></div>"
        html

window.TimeWidget = class TimeWidget extends Widget

    value: (model, name) ->
        new Date( parseInt(model.get( name )) )

window.HashWidget = class HashWidget extends Widget

    value: (model,name)->
        model.get('req')['X-Real-IP']

    renderField: (field,model,name) ->
        val = @value(model,name)
        "<td><img src='http://annihilatr.com/hash/#{val}?set=set1&size=60x60'/><div class='ip'>#{val}</div></td>"

    renderInput: (field,model,name) ->
        "<img style='display: block; margin-left: 50px;' src='http://annihilatr.com/hash/#{@value(model,name)}?set=set1&size=60x60'/>"


$.validator.addMethod( "regex" , ((value, element, regexp) -> check = false; re = new RegExp(regexp); return this.optional(element) || re.test(value)) ,"Please check your input." )

window.EntityView = class EntityView extends Backbone.View

    tagName: 'tr'

    form:
        'id':
            label: 'ID'

    initialize: ->
        @model.bind 'change',  @render
        @model.bind 'destroy', @unrender
        @model.bind 'error',   @error
    
    render: =>
        html = state = ""
        if @model.stateField then state=" state-" + @model.get(@model.stateField)
        for key, field of @form
            widget = new (field.widget or Widget)
            html += widget.renderField(field, @model, key)
        $(@el).html( html )
        @

    unrender: =>
        $(@el).undelegate().remove()
        $('.alert-message').remove()
        @trigger 'done'

    error: (model, err) =>
        $('.alert-message').remove()
        $('.container-fluid').prepend "<div class='alert-message error'>#{err.responseText or err.message or (typeof err == 'string' and err) or 'Unexpected error'}</div>"
        false

    edit: ->
        form = new FormView
            model:@model
            view:@
        form.render()
        false

    events:
        'click': 'edit'


window.Dialog = class Dialog extends Backbone.View

    events:
        'click button.cancel' :'unrender'
        'click a.close'       :'unrender'

    bindKeys: ->
        @$("input,button,select").bind "keydown", (event) =>
            keycode = event.keyCode or event.which or event.charCode
            if keycode == 13
                 @$('button.ok').click()
            if keycode == 27
                 @$('button.cancel').click()

    render: =>
        html = "<div class='modal'><div class='modal-header'><h3>#{@options.title or 'Edit'}</h3><a href='#' class='close'>×</a></div>"
        html += "<div class='modal-body'>"
        html +="</div></div>"
        $(@el).html html
        if @options.url
            $.get @options.url, (body) =>
                $('body').append @el
                @$('.modal-body').append body
                @bindKeys()
        else
                $('body').append @el
        @bindKeys()
        @

    unrender: =>
        $(@el).remove()

window.FormView = class FormView extends EntityView

    tagName: 'div'
    
    events:
        'click button.delete' :'del'
        'click button.save'   :'save'
        'click button.cancel' :'unrender'
        'click a.close'       :'unrender'

    initialize: ->
        @form = @options.view.form
        @validator = @options.view.validator
        super()
 
    render: =>
        html = "<div class='modal'><div class='modal-header'><h3>#{@options.title or 'Edit'}</h3><a href='#' class='close'>×</a></div>"
        html += "<div class='modal-body'><form onsubmit='javascript:return false'><fieldset>"
        for key, field of @form
            widget = new (field.widget or Widget)
            html += widget.render(field, @model, key)
        html += "</fieldset></form></div><div class='modal-footer'>"
        html += "<button class='btn cancel'>Cancel</button>"
        html += "<button class='btn primary save'>Save</button>&nbsp;"
        html += "<button class='btn danger delete'>Delete</button>&nbsp;"
        html +="</div></div>"
        $(@el).html html
        $('body').append @el
        if @model.isNew()
            @$('input:first').focus()
        else
            @$('input:eq(1)').focus()

        @$("input,button,select").bind "keydown", (event) =>
            keycode = event.keyCode or event.which or event.charCode
            if keycode == 13
                 @$('button.save').click()
            if keycode == 27
                 @$('button.cancel').click()
        @

    save: =>
        @$('form').validate
            rules: @validator
            showErrors: (errs)->
                $('.clearfix').removeClass('error')
                _.each errs, (msg, key)->
                    $('#f_' +key ).addClass('error')

        return unless @$('form').valid()
        isnew = @model.isNew()
        id = if isnew then $('#field-id').val() else @model.get("id")
        data = []
        for key, field of @form
            data[key] = $("#field-#{key}").val()
        data["id"] = id

        @model.save data,
            success: =>
                @model.trigger 'saved'
                @unrender()
            error: (model,err)=>
                if isnew
                    model.unset "id"
                @error( model, err)
        true

    del: =>
        @model.destroy()


window.EntityListView = class EntityListView extends Backbone.View

    el: '#content'

    constructor: (args...)->
        $(@el).undelegate().empty()
        $(document).unbind('scroll')
        super(args...)

    initialize: ->
        @item   = @options?.item or Backbone.Model
        @view   = @options?.view or EntityView
        @scroll = @options?.scroll or "paginator"
        @list = new (@options?.list or Backbone.Collection )()
        @list.perPage = @options?.perPage or 20
        @list.bind 'add', @appendItem
        @list.bind 'refresh', @render
        @list.bind 'reset', @render
        # Monkeypatch list.fetch(..) to display loading image
        @list.fetch = _.wrap @list.fetch, (fun,options) =>
            @loading( true )
            options ?= {}
            options.success = _.wrap options.success, (fun, args...) =>
                @loading( false )
                fun and fun.call( @list, args... )
            options.error = _.wrap options.error, (fun, args...) =>
                @loading( false )
                fun and fun.call( @list, args... )
            fun.call( @list, options )
        @render()

    createItem: =>
        @list.add( d = new @item() )
        d.trigger 'edit'

    appendItem: (item) =>
        itemView = new @view({'model':item})
        itemView.list = @
        @$('tbody').append itemView.render().el

    header: ->
        html = "<thead><tr>"
        for key, field of @view.prototype.form
            html += "<th class='field-#{key}'>#{field.label}</th>"
        html +="</tr></thead>"
        html

    toolbar: ->
        ""
        
    footer: ->
        "<a href='#' class='btn create'>Create New</a>"

    loading: (state)->
        if state
            if @$('tr.loading').length == 0
            	@$('tbody').append "<tr class='loading'><td colspan='100'><img src='/images/loading.gif' style='display: block; margin: 0 auto;'/></td></tr>"
        else
            @$('tr.loading').remove()

    render: =>
        html = @toolbar()
        html += "<table class='zebra-striped'>"
        html += @header()
        html += "<tbody></tbody></table>"
        if @scroll == 'paginator'
            html +="<div class='pagination'><ul></ul></div>"

        html += @footer()

        $(@el).html html

        if @scroll == 'endless'
            $(document).endlessScroll
                fireOnce: true
                fireDelay: 100
                callback: =>
                    @list.appendPage()

        _(@list.models).each ((item)->@appendItem(item)), @

        if @scroll == 'paginator'
            @renderPaginator()

    renderPaginator: ->
        info = @list.pageInfo()
        paginator = "<li class='prev#{if info.prev then "" else " disabled"}'><a href='#'>← Prev</a></li>"
        b = info.page - 5
        if b < 1 then b = 1
        e = info.page + 5
        if e > info.pages then e = info.pages+1
        for p in [b...e]
            if p == info.page
                act = " active"
            else
                act = ''
            paginator += "<li class='page#{act}'><a herf='#'>#{p}</a></li>"
        paginator += "<li class='next#{if info.next then "" else " disabled"}'><a href='#'>Next →</a></li>"
        @$('.pagination ul').html paginator

    previous: ->
        @list.previousPage()
        false

    next: ->
        @list.nextPage()
        false

    page: (event)->
        @list.setPage parseInt( $(event.target).text() )
        false

    create: ->
        item = new @item()

        form = new FormView
            model: item
            view: new @view
                model: item

        item.validate = (attrs) =>
            if @list.get( attrs.id )
                new Error("Item already exist")
            else
                false
        form.model.bind 'saved', =>
            @list.fetch()
            
        form.render()
        false

    events: ->
        'click li.prev'  :'previous'
        'click li.next'  :'next'
        'click li.page a':'page'
        'click a.create' :'create'

