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
    @timeout 3000
    @slow 1000

    before ->
        @server = new Drowsy.Server(DROWSY_URL)
        @db = @server.database(TEST_DB)
        class TestDoc extends @db.Document(TEST_COLLECTION)
        @TestDoc = TestDoc

        class TestColl extends @db.Collection(TEST_COLLECTION)
            model: TestDoc
        @TestColl = TestColl

    afterEach ->
        for sub in Wakeful.subs
            sub.cancel()
        

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

                        dsubA.state().should.equal 'pending'
                        dsubB.state().should.equal 'pending'
                        
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
                                console.log n

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
                                console.log n
                        

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
                








        