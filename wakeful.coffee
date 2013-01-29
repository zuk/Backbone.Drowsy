if window?
    # we're running in a browser
    $ = window.$
    _ = window._
    Backbone = window.Backbone
    Drowsy = window.Drowsy
    WebSocket = window.WebSocket
else
    # we're running in node
    $ = require 'jquery'
    _ = require 'underscore'
    Backbone = require 'backbone'
    Backbone.$ = $
    {Drowsy} = require './backbone.drowsy'
    WebSocket = require 'ws'


# calls the given val if it's a function, or just returns it as is otherwise
callOrRead = (val, context) -> 
    if _.isFunction(val) 
        val.call context
    else 
        val

class Wakeful
    @sync: (method, obj, options) ->
        deferredSync = $.Deferred()

        Backbone.sync(method, obj, options).done ->
            # TODO: figure out how to support delete
            data = obj.toJSON()
            if method in ['create','update','patch']
                obj.broadcast(method, data, 
                    options.origin || obj.wid || obj.defaultWid())

            deferredSync.resolve()

        return deferredSync

    @wake: (obj, wakefulUrl) ->
        throw new Error("Must provide a wakefulUrl") unless wakefulUrl?

        obj.broadcastEchoQueue = []

        _.extend obj, {
            sync: Wakeful.sync

            defaultWid: ->
                callOrRead(@url, @)+'#'+@cid

            connect: ->
                baseRx = "^wss?://[^/]+"
                fullRx = "#{baseRx}/\\w+/\\w+(/[0-9a-f]+)?"
                if wakefulUrl.match(new RegExp("#{baseRx}/?$"))
                    @socketUrl = callOrRead(@url, @).replace(new RegExp("[a-z]+://[^/]+/?"), wakefulUrl+"/")
                else if wakefulUrl.match(new RegExp(fullRx))
                    @socketUrl = wakefulUrl
                else
                    console.error wakefulUrl, "is not a valid WakefulWeasel WebSocket URL!"
                    throw "Invalid WakefulWeasel WebSocket URL!"

                deferredConnection = $.Deferred()

                if @socket? and @socket.URL is @socketUrl
                    @socket.connect()
                    return @socket
                
                @socket = new WebSocket(@socketUrl)

                broadcastHandler = (ev) =>
                    json = ev.data
                    
                    # TODO: handle parse error
                    broadcastData = JSON.parse(json)

                    @trigger 'wakeful:broadcast:received', obj, broadcastData

                    echoOf = _.find @broadcastEchoQueue, (b) -> b.bid is broadcastData.bid
                    
                    if echoOf?
                        echoIndex = _.indexOf @broadcastEchoQueue, echoOf
                        @broadcastEchoQueue.splice(echoIndex, 1) # remove echoOf
                        echoOf.resolve()

                    if broadcastData.action in ['update','patch','create']
                        # TODO: do we need to handle 'patch' differently from 'update'?
                        #       ... probably yes, at least for nested objects
                        @set broadcastData.data
                    else
                        console.warn "Don't know how to handle broadcast with action", broadcastData.action

                ackHandler = (ev) =>
                    json = ev.data

                    # TODO: handle parse error
                    ackData = JSON.parse(json)

                    if ackData.status is 'SUCCESS'
                        @socket.onmessage = broadcastHandler
                        @trigger 'wakeful:subscribed', obj, ev
                        deferredConnection.resolve()
                    else
                        err = "Subscription to #{@socketUrl} failed"
                        console.error err
                        deferredConnection.reject(err)

                @socket.onopen = (ev) =>
                    console.log "Wakeful WebSocket open for", callOrRead(@url, @)
                    
                    @trigger 'wakeful:open', obj, ev
                    @socket.onmessage = ackHandler
                    

                @socket.onclose = (ev) =>
                    console.warn "Wakeful WebSocket closed for", callOrRead(@url, @)
                    @trigger 'wakeful:disconnected', obj, ev

                @socket.error = (ev) =>
                    console.error "Wakeful WebSocket error for", callOrRead(@url, @)
                    @trigger 'wakeful:error', obj, ev

                return deferredConnection

            disconnect: ->
                if @socket and @socket.readyState is WebSocket.OPEN
                    @socket.close

            broadcast: (action, data, origin = @wid) ->
                #console.log "Broadcasting", action, ":", data

                deferredBroadcast = $.Deferred()

                bid = Drowsy.generateMongoObjectId().toString()

                send = =>
                    broadcastData = 
                        action: action 
                        data: data
                        bid: bid
                    
                    broadcastData.origin = origin if origin?

                    deferredBroadcast.bid = bid
                    @broadcastEchoQueue.push(deferredBroadcast)

                    @socket.send JSON.stringify(broadcastData)
                    @trigger 'wakeful:broadcast:sent', obj, broadcastData
                    deferredBroadcast.notify('sent')

                switch @socket.readyState
                    when WebSocket.OPEN
                        send()
                    when WebSocket.CONNECTING
                        @socket.onopen = send
                    when WebSocket.CLOSED, WebSocket.CLOSING
                        console.warn "WebSocket(#{@socket.URL}) is closing or closed... Cannot broadcast!"
                    else
                        console.error "WebSocket(#{@socket.URL}) is in a weird state... Cannot broadcast!", @socket.readyState

                return deferredBroadcast
        }

root = exports ? this
root.Wakeful = Wakeful