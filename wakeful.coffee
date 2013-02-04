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
readVal = (context, val) -> 
    if _.isFunction(val) 
        val.call context
    else 
        val

class Wakeful
    @clientId: Drowsy.generateMongoObjectId()

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

    # can't allow more than one WebSocket per scheme:host:port
    @websockets: {}

    @subs: {}

    @wake: (obj, websocketUrl) ->

        deferredConnection = $.Deferred()

        throw new Error("Must provide a websocketUrl") unless websocketUrl?
        
        obj.websocketUrl = websocketUrl

        obj.broadcastEchoQueue = []

        obj = _.extend obj,
            resourceUrl: ->
                drowsyUrl = readVal(this, @url)
                rx = new RegExp("[a-z]+://[^/]+/?/(\\w+)/(\\w+)(?:/([0-9a-f]{24}))?")
                [url, db, coll, id] = drowsyUrl.match(rx)

                if id?
                    "/#{db}/#{coll}/#{id}"
                else
                    "/#{db}/#{coll}"

            tunein: ->
                # baseRx = "^wss?://[^/]+"
                # fullRx = "#{baseRx}/\\w+/\\w+(/[0-9a-f]+)?"
                # if websocketUrl.match(new RegExp("#{baseRx}/?$"))
                #     @websocketUrl = readVal(this, @url).replace(new RegExp("[a-z]+://[^/]+/?"), websocketUrl+"/")
                # else if websocketUrl.match(new RegExp(fullRx))
                #     @websocketUrl = websocketUrl
                # else
                #     console.error websocketUrl, "is not a valid WakefulWeasel WebSocket URL!"
                #     throw "Invalid WakefulWeasel WebSocket URL!"
                

                deferredSub = $.Deferred()

                sendSubRequest = =>
                    resUrl = @resourceUrl()

                    req = 
                        type: 'SUBSCRIBE'
                        url: resUrl
                        cid: Wakeful.clientId
                    
                    @websocket.send JSON.stringify(req)

                    # TODO: might want to get some sort of ackwnoledgement from weasel
                    Wakeful.subs[resUrl] ?= []
                    Wakeful.subs[resUrl].push(this)

                    @trigger 'wakeful:subscription', req
                    deferredSub.resolve()

                switch @websocket.readyState
                    when WebSocket.OPEN
                        sendSubRequest()
                    when WebSocket.CONNECTING
                        @websocket.addEventListener('open', sendSubRequest)
                    when WebSocket.CLOSED
                        @websocket.open()
                        @websocket.addEventListener('open', sendSubRequest)
                    when WebSocket.CLOSING
                        console.warn "WebSocket(#{@websocket.URL}) is closing... Cannot send request!"
                    else
                        console.error "WebSocket(#{@websocket.URL}) is in a weird state... Cannot send request!", @websocket.readyState

                return deferredSub

            broadcast: (action, data) =>
                deferredPub = $.Deferred()

                send = =>
                    req = 
                        type: 'PUBLISH'
                        action: action 
                        data: data
                        url: readVal(this, @url)
                    
                    @broadcastEchoQueue.push(deferredPub)

                    @websocket.send JSON.stringify(req)
                    @trigger 'wakeful:broadcast:sent', obj, req
                    deferredPub.notify('sent')

                switch @websocket.readyState
                    when WebSocket.OPEN
                        send()
                    when WebSocket.CONNECTING
                        @websocket.onopen = send
                    when WebSocket.CLOSED, WebSocket.CLOSING
                        console.warn "WebSocket(#{@websocket.URL}) is closing or closed... Cannot send request!"
                    else
                        console.error "WebSocket(#{@websocket.URL}) is in a weird state... Cannot send request!", @websocket.readyState

                return deferredPub

        if Wakeful.websockets[websocketUrl]?
            obj.websocket = Wakeful.websockets[websocketUrl]
        else
            websocket = new WebSocket(websocketUrl)

            obj.websocket = websocket
            Wakeful.websockets[websocketUrl] = websocket

            # like .close(), but returns a deferred that resolves only 
            # once we're definitely closed
            websocket.ensuredClose = ->
                deferredClose = $.Deferred()
                if @readyState is WebSocket.CLOSED
                    deferredClose.resolve()
                else
                    onclose = (ev) =>
                        @removeEventListener 'close', onclose
                        deferredClose.resolve()
                    @addEventListener 'close', onclose
                    @close() if @readyState is WebSocket.OPEN

                return deferredClose

            websocket.onmessage = (ev) =>
                # TODO: handle parse error
                bcast = JSON.parse(ev.data)

                for subObj in Wakeful.subs[bcast.url]
                    subObj.trigger 'wakeful:broadcast:received', bcast

                    echoOf = _.find subObj.broadcastEchoQueue, (b) -> b.bid is bcast.bid
                    
                    if echoOf?
                        echoIndex = _.indexOf subObj.broadcastEchoQueue, echoOf
                        subObj.broadcastEchoQueue.splice(echoIndex, 1) # remove echoOf
                        echoOf.resolve()

                    if bcast.action in ['update','patch','create']
                        # TODO: do we need to handle 'patch' differently from 'update'?
                        #       ... probably yes, at least for nested objects
                        subObj.set bcast.data
                    else
                        console.warn "Don't know how to handle broadcast with action", bcast.action

        if obj.websocket.readyState is WebSocket.OPEN
            console.log "resolving right away"
            deferredConnection.resolve()
        else
            obj.websocket.addEventListener 'open', (ev) ->
                deferredConnection.resolve()
                obj.websocket.removeEventListener 'open', this
            obj.websocket.addEventListener 'error', (ev) ->
                console.error ev
                deferredConnection.reject(ev)
                obj.websocket.removeEventListener 'error', this
            obj.websocket.open()

        obj.websocket.addEventListener 'close', (ev) ->
            console.warn "Wakeful WebSocket closed for", obj.resourceUrl(), ev
            obj.websocket.removeEventListener('close')
            #@trigger 'wakeful:disconnected', obj, ev

        # obj.websocket.addEventListener 'error', (ev) ->
        #     console.error "Wakeful WebSocket error for", obj.resourceUrl(), ev
        #     #@trigger 'wakeful:error', obj, ev

        obj.sync = Wakeful.sync

        return deferredConnection

root = exports ? this
root.Wakeful = Wakeful