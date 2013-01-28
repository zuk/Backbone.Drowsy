if window?
    # we're running in a browser
    $ = window.$
    _ = window._
    Backbone = window.Backbone
else
    # we're running in node
    $ = require('jquery');
    _ = require 'underscore'
    Backbone = require('backbone')
    Backbone.$ = $

sync = (method, obj, options) ->
    options.success = (data, status, xhr) ->
        # TODO: figure out how to support delete
        if method in ['create','update','patch']
            obj.broadcast(method, data, options.origin)

        options.success(data, status, xhr) if options.success?

    Backbone.sync()

wake = (obj, wakefulUrl) ->
    obj.extend
        sync: sync

        connect: ->
            baseRx = "^wss?://[^/]+"
            fullRx = "#{baseRx}/\\w+/\\w+(/[0-9a-f]+)?"
            if wakefulUrl.match(new RegExp("#{baseRx}/?$"))
                @socketUrl = @url().replace(new RegExp("[a-z]+://[^/]+/?"), "/#{wakefulUrl}")
            else if wakefulUrl.match(new RegExp(fullRx))
                @socketUrl = wakefulUrl
            else
                console.error wakefulUrl, "is not a valid WakefulWeasel WebSocket URL!"
                throw "Invalid WakefulWeasel WebSocket URL!"

            if @socket? and @socket.URL is @socketUrl
                @socket.connect()
                return @socket

            @socket = new WebSocket(@socketUrl)

            @socket.onmessage = (json) =>
                # TODO: handle parse error
                broadcast = JSON.parse(json)

                if broadcast.action in ['update','patch']
                    # TODO: do we need to handle 'patch' differently from 'update'?
                    #       ... probably yes, at least for nested objects
                    @set broadcast.data
                else
                    console.warn "Don't know how to handle broadcast with action",broadcast.action
                    return

            return @socket

        disconnect: ->
            if @socket and @socket.readyState is WebSocket.OPEN
                @socket.close

        broadcast: (action, data, origin = @origin) ->
            console.log "Broadcasting", action, ":", data
            send = ->
                broadcast = 
                    action: action 
                    data: data
                
                broadcast.origin = origin if origin?

                @socket.send JSON.stringify(broadcast)

            switch @socket.readyState
                when WebSocket.OPEN
                    send()
                when WebSocket.CONNECTING
                    @socket.onopen = send
                when WebSocket.CLOSED, WebSocket.CLOSING
                    console.warn "WebSocket(#{@socket.URL}) is closing or closed... Cannot broadcast!"
                else
                    console.error "WebSocket(#{@socket.URL}) is in a weird state... Cannot broadcast!", @socket.readyState



root = exports ? this
root.wake = wake
root.sync = sync