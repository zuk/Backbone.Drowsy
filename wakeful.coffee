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
                    obj.broadcast(method, obj.toJSON())
                when 'patch'
                    obj.broadcast(method, changed)

            # FIXME: maybe don't resolve until .broadcast() resolves?
            deferredSync.resolve()

        return deferredSync


    @wake: (obj, fayeUrl, options = {}) ->

        if obj.fayeUrl? and obj.fayeUrl is fayeUrl
            console.log obj,"is already awake... skipping"
            return
        
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

                # don't need to stringify data... Faye does it for us
                #data = JSON.stringify(data) unless typeof data is 'string'

                # make sure that we always have an id attached so that
                # we can identify who this data refers to
                if not data._id? and @id?
                    data._id = @id

                bcast = 
                    action: action
                    data: data
                    bid: bid
                    origin: @origin()

                @broadcastEchoQueue.push(deferredPub)

                toChannel = @subscriptionUrl()
                if this instanceof Drowsy.Collection
                    toChannel = toChannel.replace(/\*$/,'~') # hack to get channel subscription to hear its own broadcasts
                pub = @faye.publish toChannel, bcast

                @trigger 'wakeful:broadcast:sent', bcast
                deferredPub.notify 'sent'
                
                pub.callback =>
                    # NOTE: Usually this will get executed AFTER deferredPub.
                    #       ... not sure why, but Faye seems to execute this callback
                    #       some time after broadcasting the pub.
                    #       As a consequence, a .progress() handler bound to
                    #       deferredPub for 'confirmed' doesn't normally get triggered, 
                    #       since it will have resolved already.
                    @trigger 'wakeful:broadcast:confirmed', bcast
                    deferredPub.notify 'confirmed'

                pub.errback (err) =>
                    console.warn "Broadcast ##{bid} failed!", err, bcast
                    @trigger 'wakeful:broadcast:error', bcast, err
                    deferredPub.reject err

                deferredPub.pub = pub
                deferredPub.bid = bid

                return deferredPub


            receiveBroadcast: (bcast) -> 
                echoOf = _.find @broadcastEchoQueue, (defPub) -> defPub.bid is bcast.bid
                
                if echoOf?
                    echoIndex = _.indexOf @broadcastEchoQueue, echoOf
                    @broadcastEchoQueue.splice(echoIndex, 1) # remove echoOf
                    @trigger 'wakeful:broadcast:echo', bcast
                    echoOf.resolve()
                    return
                
                # FIXME: this probably doesn't actually do anything since messages to
                #   self would be caught by the echoOf check
                if bcast.origin? and bcast.origin is @origin()
                    console.warn @origin(),"received broadcast from self... how did this happen?"
                    return

                @trigger 'wakeful:broadcast:received', bcast

                switch bcast.action
                    when 'update','patch','create'
                        if this instanceof Drowsy.Document
                            @set bcast.data
                        else 
                            # this is a collection
                            if _.isArray(bcast.data)
                                docs = bcast.data
                                if bcast.action is 'patch' and not bcast.data?
                                    console.error "PATCH received by collection will be ignored because the broadcast data did not include a document id (_id)", bcast
                                    return
                            else
                                docs = [bcast.data]
                            @update(docs, remove: false)
                    else
                        console.warn "Don't know how to handle broadcast with action", bcast.action

            origin: ->
                readVal(this, @url) + "#" + @faye.getClientId()

        unless options.tunein is false
            obj.tunein()

root = exports ? this
root.Wakeful = Wakeful