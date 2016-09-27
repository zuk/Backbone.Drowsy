if window?
    # we're running in a browser
    $ = window.$
    _ = window._
    Backbone = window.Backbone
    Faye = window.Faye
    Drowsy = window.Drowsy
    Wakeful = window.Wakeful
    WebSocket = window.WebSocket
    DROWSY_URL = window.DROWSY_URL
    WEASEL_URL = window.WEASEL_URL
else
    # we're running in node
    $ = require 'jquery'
    _ = require 'underscore'
    Backbone = require 'backbone'
    Backbone.$ = $
    Faye = require 'faye'
    {Drowsy} = require '../backbone.drowsy'
    {Wakeful} = require '../wakeful'
    should = require('chai').should()
    DROWSY_URL = process.env.DROWSY_URL
    WEASEL_URL = process.env.WEASEL_URL

DROWSY_URL = "http://localhost:9292" unless DROWSY_URL?
WEASEL_URL = "http://localhost:7777/faye" unless WEASEL_URL?
TEST_DB = 'drowsy_test'
TEST_COLLECTION = 'tests'

# TEST_USERNAME = "encorelab"
# TEST_PASSWORD = "encorepw"

if TEST_USERNAME? and TEST_PASSWORD?
    {Buffer} = require 'buffer'
    btoa = (str) ->
        (new Buffer(str || "", "ascii")).toString "base64"

    Backbone.$.ajaxSetup
        beforeSend: (xhr) ->
            xhr.setRequestHeader 'Authorization', 
                'Basic ' + btoa(TEST_USERNAME+':'+TEST_PASSWORD);

describe 'Wakeful', ->
    @timeout 6000
    @slow 1000

    before (done) ->
        @server = new Drowsy.Server(DROWSY_URL)
        @db = @server.database(TEST_DB)
        class TestDoc extends @db.Document(TEST_COLLECTION)
        @TestDoc = TestDoc

        class TestColl extends @db.Collection(TEST_COLLECTION)
            model: TestDoc
        @TestColl = TestColl

        # Drop the test collection if it exists
        Backbone.$.ajax("#{DROWSY_URL}/#{TEST_DB}/#{TEST_COLLECTION}", type: 'DELETE')
            .always -> # always, because we ignore the error raised if the DELETE fails because the collection doesn't exist
                # Recreate the test collection
                Backbone.$.ajax("#{DROWSY_URL}/#{TEST_DB}", type: 'POST', data: {collection: TEST_COLLECTION})
                    .fail(done)
                    .done(-> done())


    afterEach ->
        # for sub in Wakeful.subs
        #     sub.cancel()

        for url,client of Wakeful.fayeClients
            client.disconnect()
        

    describe ".wake", ->
        it 'should enhance Drowsy.Document with wakeful functionality', ->
            doc = new @TestDoc()

            Wakeful.wake doc, WEASEL_URL

            doc.should.have.property 'tunein'
            doc.tunein.should.be.a 'function'

            doc.should.have.property 'broadcast'
            doc.broadcast.should.be.a 'function'

        it 'should automatically tunein the object', (done) ->
            doc = new @TestDoc()

            dsub = Wakeful.wake doc, WEASEL_URL

            dsub.should.have.property 'resolve'
            dsub.resolve.should.be.a 'function'

            dsub.done ->
                done()

        # TODO: figure out some way to test the transport:down and transport:up events...


        describe "#tunein", ->
            it 'should return a $.Deferred', (done) ->
                doc = new @TestDoc()

                Wakeful.wake doc, WEASEL_URL, tunein: false

                dsub = doc.tunein()

                # duck typing check
                dsub.should.have.property 'resolve'
                dsub.resolve.should.be.a 'function'

                dsub.done -> done()

            it 'should be able to subscribe to multiple documents and collections', (done) ->
                doc1 = new @TestDoc()
                doc2 = new @TestDoc()
                coll1 = new @TestColl()
                coll2 = new @TestColl()

                Wakeful.wake doc1, WEASEL_URL, tunein: false
                Wakeful.wake doc2, WEASEL_URL, tunein: false
                Wakeful.wake coll1, WEASEL_URL, tunein: false
                Wakeful.wake coll2, WEASEL_URL, tunein: false
                
                dsubDoc1 = doc1.tunein()
                dsubDoc2 = doc2.tunein()
                dsubColl1 = coll1.tunein()
                dsubColl2 = coll2.tunein()

                $.when(dsubDoc1, dsubDoc2, dsubColl1, dsubColl2).always ->
                    dsubDoc1.state().should.equal 'resolved'
                    doc1.should.have.property 'sub'
                    doc1.sub.should.be.an.instanceof Faye.Subscription

                    dsubDoc2.state().should.equal 'resolved'
                    doc2.should.have.property 'sub'
                    doc2.sub.should.be.an.instanceof Faye.Subscription
                    
                    dsubColl1.state().should.equal 'resolved'
                    coll1.should.have.property 'sub'
                    coll1.sub.should.be.an.instanceof Faye.Subscription

                    dsubColl2.state().should.equal 'resolved'
                    coll2.should.have.property 'sub'
                    coll2.sub.should.be.an.instanceof Faye.Subscription

                    done()

            it 'should not allow tuning in for a Drowsy.Document that does not have an id', ->
                # can't call tunein for id-less document because we can't subscribe to a proper channel

                doc = new @TestDoc()

                Wakeful.wake doc, WEASEL_URL, tunein: false

                doc.set('_id', null)

                (->
                    doc.tunein()
                ).should.throw(Error)

        describe "#broadcast", ->
            it "should notify when sent, and resolve when echoed", (done) ->
                doc = new @TestDoc()
                doc.save().done ->
                    dsub = Wakeful.wake doc, WEASEL_URL
                    dsub.done ->
                        rand = Math.random()
                        doc.set 'foo', rand

                        sent = false

                        dpub = doc.broadcast 'update', doc.toJSON()
                        # FIXME: dsub.progress is never triggered because
                        #       Faye echoes back the broadcast before the
                        #       'sent' callback that calld dsub.notify()
                        #       is called.
                        dpub.progress (note) ->
                            note.should.equal 'sent'
                            sent = true
                        dpub.always ->
                            dpub.state().should.equal 'resolved'
                            #sent.should.be.true
                            done()
                        
            it "should not broadcast for a Drowsy.Document that does not have an id", (done) ->
                doc = new @TestDoc()
                doc.save().done ->
                    dsub = Wakeful.wake doc, WEASEL_URL
                    dsub.done ->
                        rand = Math.random()
                        doc.set 'foo', rand

                        sent = false

                        doc.set('_id', null)

                        dpub = doc.broadcast 'update', doc.toJSON()
                        # FIXME: dsub.progress is never triggered because
                        #       Faye echoes back the broadcast before the
                        #       'sent' callback that calld dsub.notify()
                        #       is called.
                        dpub.progress (note) ->
                            sent = true
                        dpub.always ->
                            sent.should.be.false
                            dpub.state().should.equal 'rejected'
                            done()

            # it "should push onto the broadcastEchoQueue and then pop when echo received", (done) ->
            #     doc = new @TestDoc()
            #     doc.save().done ->
            #         Wakeful.wake doc, WEASEL_URL
            #         doc.connect().done ->
            #             rand = Math.random()
            #             doc.set 'foo', rand

            #             sent1 = false
            #             sent2 = false
            #             doc.broadcastEchoQueue.should.be.empty

            #             bc1 = doc.broadcast 'update', doc.toJSON()

            #             doc.broadcastEchoQueue.length.should.equal 1

            #             bc2 = doc.broadcast 'update', doc.toJSON()

            #             doc.broadcastEchoQueue.length.should.equal 2

            #             bc1.progress (note) ->
            #                 doc.broadcastEchoQueue.length.should.be.within(1,2)
            #                 note.should.equal 'sent'
            #                 sent1 = true
            #             bc2.progress (note) ->
            #                 doc.broadcastEchoQueue.length.should.be.within(1,2)
            #                 note.should.equal 'sent'
            #                 sent2 = true

            #             $.when(bc1, bc2).then ->
            #                 sent1.should.be.true
            #                 sent2.should.be.true
            #                 doc.broadcastEchoQueue.should.be.empty
            #                 done()

                        

            it "should send an update from one Drowsy.Document to another Drowsy.Document with the same URL", (done) ->
                doc1 = new @TestDoc()
                doc2 = new @TestDoc()

                doc1.save().done ->
                    doc2.set '_id', doc1.id

                    # doc1 and doc2 should have the same url since they are the same doc
                    doc2.url().should.equal doc1.url()
                    
                    doc2.save().done ->
                        dsubA = Wakeful.wake doc1, WEASEL_URL
                        dsubB = Wakeful.wake doc2, WEASEL_URL

                        # note that these will probably already be subscribed
                        
                        # when both have subscribed
                        $.when(dsubA, dsubB).done ->
                            rand = Math.random()
                            doc1.set('foo', rand)
                            doc1.get('foo').should.equal rand
                            doc2.has('foo').should.be.false

                            doc2.on 'change', ->
                                doc2.get('foo').should.equal rand
                                done()

                            bc = doc1.broadcast 'update', doc1.toJSON()
                            bc.progress (n) ->
                                # console.log n

            it "should send an update from a Drowsy.Document to its containing Drowsy.Collection", (done) ->
                doc1 = new @TestDoc()
                coll1 = new @TestColl()

                doc1.save().done ->
                        
                    dsubA = Wakeful.wake doc1, WEASEL_URL
                    dsubB = Wakeful.wake coll1, WEASEL_URL

                    dsubA.state().should.equal 'pending'
                    dsubB.state().should.equal 'pending'
                    
                    # when both have subscribed
                    $.when(dsubA, dsubB).done ->
                        coll1.fetch().done ->

                            rand = Math.random()
                            doc1.set('foo', rand)
                            doc1.get('foo').should.equal rand

                            coll1.get(doc1.id).should.not.have.property 'foo'

                            coll1.on 'change', ->
                                coll1.get(doc1.id).get('foo').should.equal rand
                                done()

                            bc = doc1.broadcast 'update', doc1.toJSON()
                            bc.progress (n) ->
                                # console.log n
                        

    describe ".sync", ->
        it "should sync an update across existing Drowsy.Documents", (done) ->
            doc1 = new @TestDoc()
            doc2 = new @TestDoc()

            doc1.set('bar', 'a')

            doc1.save().done ->
                doc2.set '_id', doc1.id
                doc2.fetch().done ->
                    doc1.toJSON().should.eql doc2.toJSON()

                    dsub1 = Wakeful.wake doc1, WEASEL_URL
                    dsub2 = Wakeful.wake doc2, WEASEL_URL

                    # this change will be reversed by the sync
                    doc2.set('bar', 'b')

                    # when both have subscribed
                    $.when(dsub1, dsub2).done ->
                        rand = Math.random()
                        doc1.set 'foo', rand
                        
                        doc2.on 'change', ->
                            doc2.get('foo').should.equal rand
                            doc2.get('bar').should.equal 'a'
                            done()

                        doc1.save()

        it "should sync a patch across existing Drowsy.Documents", (done) ->
            doc1 = new @TestDoc()
            doc2 = new @TestDoc()


            doc1.set('foo', 'ALPHA')
            doc1.set('bar', 'a')

            doc1.save().done ->
                doc2.set '_id', doc1.id
                doc2.fetch().done ->
                    doc1.toJSON().should.eql doc2.toJSON()

                    dsub1 = Wakeful.wake doc1, WEASEL_URL
                    dsub2 = Wakeful.wake doc2, WEASEL_URL

                    # this change will NOT be reversed by the sync, even though we don't persist it
                    doc2.set('bar', 'b')

                    # when both have subscribed
                    $.when(dsub1, dsub2).done ->

                        # 'patch' request ignores attributes set with .set()
                        # ... need to specify the attrs we want patched in 
                        # the first argument to save() ...
                        #doc1.set 'foo', 'BETA'
                        
                        doc2.on 'change', ->
                            doc2.get('foo').should.equal 'BETA'
                            doc2.get('bar').should.equal 'b'
                            done()

                        # ... like so
                        doc1.save({foo: 'BETA'}, {patch: true, broadcast: true})
                        # NOTE: need to also set broadcast flag when sending a patch!
                        #   The following will fail, because .sync is never triggered:
                        #
                        # doc1.save({foo: rand}, {patch: true})


        it "should sync an update from a Drowsy.Document to a Drowsy.Collection", (done) ->
            doc1 = new @TestDoc()
            coll1 = new @TestColl()

            doc1.save().done ->
                coll1.fetch().done ->

                    coll1.get(doc1.id).toJSON().should.eql doc1.toJSON()

                    dsub1 = Wakeful.wake doc1, WEASEL_URL
                    dsub2 = Wakeful.wake coll1, WEASEL_URL

                    # when both have subscribed
                    $.when(dsub1, dsub2).done ->

                        rand = Math.random()
                        doc1.set 'foo', rand
                        
                        coll1.get(doc1.id).on 'change', ->
                            coll1.get(doc1.id).get('foo').should.equal rand
                            done()

                        doc1.save()

        it "should trigger an 'add' event on a Drowsy.Collection when a new Drowsy.Document is created in it", (done) ->
            doc1 = new @TestDoc()
            coll1 = new @TestColl()

            dsub1 = Wakeful.wake doc1, WEASEL_URL
            dsub2 = Wakeful.wake coll1, WEASEL_URL

            $.when(dsub1, dsub2).done ->

                coll1.on 'add', ->
                    done()

                doc1.save()

        it "should trigger an 'change' event on a Drowsy.Collection when a Drowsy.Document in it changes", (done) ->
            doc1 = new @TestDoc()
            coll1 = new @TestColl()

            dsub1 = Wakeful.wake doc1, WEASEL_URL
            dsub2 = Wakeful.wake coll1, WEASEL_URL

            doc1.save({foo: 'bar'}).done ->

                $.when(dsub1, dsub2).done ->

                    coll1.on 'change', ->
                        done()

                    doc1.save({foo: 'faa'})

        it "should broadcast original Drowsy.Document attributes if they are altered in a save() callback", (done) ->
            doc1 = new @TestDoc()
            doc2 = new @TestDoc()

            doc1.set('bar', 'a')

            successCallbackThatModifiesAttributes = ->
                #doc1.clear()
                doc1.set('bar', 'z')

            doc2.set '_id', doc1.id

            doc2.on 'wakeful:broadcast:received', (bcast) ->
                bcast.data.bar.should.equal 'a'
                done()

            dsub1 = Wakeful.wake doc1, WEASEL_URL
            dsub2 = Wakeful.wake doc2, WEASEL_URL

            doc1.save({}, success: successCallbackThatModifiesAttributes)

        it "should broadcast an update when changes are given in first argument to save()", (done) ->
            doc1 = new @TestDoc()
            doc2 = new @TestDoc()

            # doc1.on 'all', (ev, data) -> console.log("#{Date.now()}", 'doc1', ev)
            # doc2.on 'all', (ev, data) -> console.log("#{Date.now()}", 'doc2', ev)

            doc1.save().done ->
                doc2.set '_id', doc1.id

                $.when(
                    doc1.wake(WEASEL_URL),
                    doc2.wake(WEASEL_URL)
                ).done ->
                    doc2.on 'change', ->
                        doc2.get('foo').should.equal 'ALPHA'
                        done()

                    doc1.set 'foo', 'BETA'

                    doc1.save(foo: 'ALPHA', bar: 'a')

        it "should NOT braodcast an update when patching and no changes were made", (done) ->
            doc1 = new @TestDoc()
            doc2 = new @TestDoc()

            doc1.save().done ->
                doc2.set '_id', doc1.id

                $.when(
                    doc1.wake(WEASEL_URL),
                    doc2.wake(WEASEL_URL)
                ).done ->
                    changeFired = false
                    doc2.on 'change', ->
                        changeFired = true

                    doc1.save({}, patch: true).done ->
                        setTimeout (-> 
                                changeFired.should.be.false
                                done()
                            ), 500

        it "should correctly sync an update with a Date ($date) object", (done) ->
            doc1 = new @TestDoc()
            doc2 = new @TestDoc()

            doc1.save().done ->
                doc2.set '_id', doc1.id

                $.when(
                    doc1.wake(WEASEL_URL),
                    doc2.wake(WEASEL_URL)
                ).done ->
                    theDate = new Date()

                    doc2.on 'change', ->
                        doc2.get('this_is_a_date').should.be.an.instanceof Date
                        doc2.get('this_is_a_date').toLocaleString().should.equal theDate.toLocaleString()
                        done()

                    doc1.set 'this_is_a_date', theDate

                    doc1.save()

        it "should correctly sync a PATCH update with a Date ($date) object", (done) ->
            doc1 = new @TestDoc()
            doc2 = new @TestDoc()

            doc1.save().done ->
                doc2.set '_id', doc1.id

                $.when(
                    doc1.wake(WEASEL_URL),
                    doc2.wake(WEASEL_URL)
                ).done ->
                    theDate = new Date()

                    doc2.on 'change', ->
                        doc2.get('this_is_a_date').should.be.an.instanceof Date
                        doc2.get('this_is_a_date').toLocaleString().should.equal theDate.toLocaleString()
                        done()

                    doc1.set 'this_is_a_date', theDate

                    doc1.save({}, {patch: true})

        it "should correctly sync an update with a Date ($date) object when the receiver is a Collection", (done) ->
            doc1 = new @TestDoc()
            coll1 = new @TestColl()

            doc1.save().done ->
                coll1.fetch().done ->
                    $.when(
                        doc1.wake(WEASEL_URL),
                        coll1.wake(WEASEL_URL)
                    ).done ->
                        theDate = new Date()

                        coll1.on 'change', ->
                            coll1.get(doc1.id).get('this_is_a_date').should.be.an.instanceof Date
                            coll1.get(doc1.id).get('this_is_a_date').toLocaleString().should.equal theDate.toLocaleString()
                            done()

                        #doc1.set 'this_is_a_date', theDate
                        #doc1.save()
                        doc1.save(this_is_a_date: theDate)

        it "should trigger a 'sync' event on successful save()", (done) ->
            doc1 = new @TestDoc()

            saveSync = false
            doc1.wake(WEASEL_URL).done ->
                doc1.once 'sync', ->
                    saveSync = true

                doc1.save().done ->
                    saveSync.should.be.true
                    done()

        it "should trigger a 'sync' event on successful fetch()", (done) ->
            doc1 = new @TestDoc()

            fetchSync = false
            doc1.save().done ->
                doc1.wake(WEASEL_URL).done ->
                    doc1.once 'sync', ->
                        fetchSync = true

                    doc1.fetch().done ->
                        fetchSync.should.be.true
                        done()


        it "should trigger a 'sync' event on successful fetch() and save()", (done) ->
            doc1 = new @TestDoc()

            doc1.wake(WEASEL_URL).done ->
                # doc1.on 'all', (ev) -> console.log(ev)

                saveSync1 = false
                saveSync2 = false
                fetchSync = false

                # should be triggered by the first .save() call... note that this gets triggered
                # before the data is actually written to disk by Wakeful through Drowsy. Since
                # we need to wait until the data is written to disk before calling .fetch(), we
                # have to listen for 'wakeful:broadcast:echo' before we can do anything.
                doc1.once 'sync', ->
                    saveSync1 = true

                # wakeful:broadcast:echo gets triggered once we receive back our own create/update broadcast
                doc1.once 'wakeful:broadcast:echo', (bcast) ->
                    bcast.action.should.equal('update') # FIXME: this should actually be 'create', not 'update', since this will be a new doc

                    doc1.once 'sync', -> # should be triggered by the .fetch() call
                        fetchSync = true

                    doc1.fetch()
                    .fail(done)
                    .done ->
                        doc1.once 'sync', -> # should be triggered by the second .sync() call
                            saveSync2 = true

                            saveSync1.should.be.true
                            saveSync2.should.be.true
                            fetchSync.should.be.true

                            done()

                        doc1.save({}, patch: true)


                doc1.save()

        it "should clear dirtyAttributes on successful save() and fetch()", (done) ->
            doc1 = new @TestDoc()
            doc2 = new @TestDoc()

            # doc1.on 'all', (ev, data) -> console.log("#{Date.now()}", 'doc1', ev)
            # doc2.on 'all', (ev, data) -> console.log("#{Date.now()}", 'doc2', ev)


            $.when(
                doc1.save(),
                doc2.save()
            ).done ->
                $.when(
                    doc1.wake(WEASEL_URL),
                    doc2.wake(WEASEL_URL)
                ).done ->

                    doc1.set('foo', 1)
                    doc2.set('foo', 'a') # set different values on different instances make sure that
                                         # dirtyAttributes reset is done on the correct instance
                    doc1.dirtyAttributes().should.eql {foo: 1}
                    doc2.dirtyAttributes().should.eql {foo: 'a'}

                    doc1.once 'sync', ->
                        doc1.dirtyAttributes().should.eql {}
                        doc2.dirtyAttributes().should.eql {foo: 'a'}

                        doc1.set('foo', 2)

                        doc1.once 'sync', ->
                            doc1.dirtyAttributes().should.eql {}
                            doc2.dirtyAttributes().should.eql {foo: 'a'}

                            doc1.set('foo', 3)

                            doc1.once 'sync', ->
                                doc1.dirtyAttributes().should.eql {}
                                doc2.dirtyAttributes().should.eql {foo: 'a'}

                                done()

                            doc1.save({}, patch: true)

                        doc1.fetch()

                    doc1.save()
                

        