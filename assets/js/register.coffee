$ ->
    $("#register-form").validate rules:
        uid:
            regexp: '^[a-zA-Z0-9_]+$'
            remote: '/validate/uid'
