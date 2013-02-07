if window?
    # we're running in a browser
    $ = window.$
    _ = window._
    Backbone = window.Backbone
    Drowsy = window.Drowsy
    Faye = window.Faye
else
    # we're running in node
    $ = require 'jquery'
    _ = require 'underscore'
    Backbone = require 'backbone'
    Backbone.$ = $
    {Drowsy} = require './backbone.drowsy'
    Faye = require 'faye'


# calls the given val if it's a function, or just returns it as is otherwise
readVal = (context, val) -> 
    if _.isFunction(val) 
        val.call context
    else 
        val

# FIXME: under Firefox, Faye seems to occassionally use JSONP instead of WebSockets
#           which makes Mocha complain about globals being introduced inside code (_jsonp_ vars)
class Wakeful
    # A list of all Faye.Subscriptions crated by Wakeful objects.
    # We keep this list in order to close all subs at the end of each
    # test/spec.
    @subs: []

    @sync: (method, obj, options) ->
        deferredSync = $.Deferred()

        changed = obj.changed

        Backbone.sync(method, obj, options).done ->
            # TODO: figure out how to support delete
            switch method
                when 'create','update'
                    data = obj.toJSON()
                    obj.broadcast(method, data)
                when 'patch'
                    obj.broadcast(method, changed)

            # FIXME: maybe don't resolve until .broadcast() resolves?
            deferredSync.resolve()

        return deferredSync


    @wake: (obj, fayeUrl, options = {}) ->

        throw new Error("Must provide a fayeUrl") unless fayeUrl?
        
        obj.fayeUrl = fayeUrl
       
        obj.broadcastEchoQueue = []

        obj.faye = new Faye.Client(fayeUrl)

        obj.sync = Wakeful.sync

        obj = _.extend obj,
            subscriptionUrl: ->
                drowsyUrl = readVal(this, @url)
                rx = new RegExp("[a-z]+://[^/]+/?/(\\w+)/(\\w+)(?:/([0-9a-f]{24}))?")
                [url, db, coll, id] = drowsyUrl.match(rx)

                if id?
                    "/#{db}/#{coll}/#{id}"
                else
                    "/#{db}/#{coll}/*"

            tunein: ->
                # baseRx = "^wss?://[^/]+"
                # fullRx = "#{baseRx}/\\w+/\\w+(/[0-9a-f]+)?"
                # if fayeUrl.match(new RegExp("#{baseRx}/?$"))
                #     @fayeUrl = readVal(this, @url).replace(new RegExp("[a-z]+://[^/]+/?"), fayeUrl+"/")
                # else if fayeUrl.match(new RegExp(fullRx))
                #     @fayeUrl = fayeUrl
                # else
                #     console.error fayeUrl, "is not a valid WakefulWeasel WebSocket URL!"
                #     throw "Invalid WakefulWeasel WebSocket URL!"

                deferredSub = $.Deferred()

                @sub = @faye.subscribe @subscriptionUrl(), _.bind(@receiveBroadcast, this)

                @sub.callback ->
                    deferredSub.resolve()
                @sub.errback (err) -> 
                    deferredSub.reject(err)

                Wakeful.subs.push @sub

                return deferredSub

            tuneout: ->
                sub.cancel()
                delete @sub

            broadcast: (action, data) ->
                deferredPub = $.Deferred()

                # bid = broadcast id
                # just using the Mongo ObjectId as a pseudo-unique string; 
                # it has nothing to do with MongoDB here
                bid = Drowsy.generateMongoObjectId()

                bcast = 
                    action: action
                    data: data
                    bid: bid

                @broadcastEchoQueue.push(deferredPub)

                pub = @faye.publish @subscriptionUrl(), bcast
                
                pub.callback =>
                    # NOTE: Usually this will get executed AFTER deferredPub.
                    #       ... not sure why, but Faye seems to execute this callback
                    #       some time after broadcasting the pub.
                    #       As a consequence, a .progress() handler bound to
                    #       deferredPub doesn't normally get triggered, since
                    #       it will resolve first.
                    @trigger 'wakeful:broadcast:sent', bcast
                    deferredPub.notify 'sent'

                pub.errback (err) =>
                    console.warn "Broadcast ##{bid} failed!", err, bcast
                    @trigger 'wakeful:broadcast:error', bcast, err
                    deferredPub.reject err

                deferredPub.pub = pub
                deferredPub.bid = bid

                return deferredPub


            receiveBroadcast: (bcast) -> 
                @trigger 'wakeful:broadcast:received', bcast

                echoOf = _.find @broadcastEchoQueue, (defPub) -> defPub.bid is bcast.bid
                
                if echoOf?
                    echoIndex = _.indexOf @broadcastEchoQueue, echoOf
                    @broadcastEchoQueue.splice(echoIndex, 1) # remove echoOf
                    echoOf.resolve()

                switch bcast.action
                    when 'update','patch','create'
                        # TODO: do we need to handle 'patch' differently from 'update'?
                        #       ... probably yes, at least for nested objects
                        if @set?
                            @set bcast.data
                        else
                            @update(bcast.data, remove: false)
                    else
                        console.warn "Don't know how to handle broadcast with action", bcast.action


        unless options.tunein is false
            obj.tunein()

root = exports ? this
root.Wakeful = Wakeful