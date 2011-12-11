$ ->
    $("#login-form").validate rules:
        uid:
            regexp: '^[a-zA-Z0-9_]+$'
