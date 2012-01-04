exports.init = (app, cb)->
    return cb(null) if not app
    app.get '/registry/:id', (req, resp)->
        resp.send {"error":"not_found","reason":"missing"}, 404

    app.put '/registry/:id', (req, resp)->
        exports.log.info "Published package: ", req.body
        resp.send [ req.body, {"ok":"Package published"} ]

    cb and cb(null)
