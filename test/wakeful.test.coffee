if window?
    # we're running in a browser
    $ = window.$
    _ = window._
    Backbone = window.Backbone
    Drowsy = window.Drowsy
    Wakeful = window.Wakeful
    WebSocket = window.WebSocket
else
    # we're running in node
    $ = require 'jquery'
    _ = require 'underscore'
    Backbone = require 'backbone'
    Backbone.$ = $
    {Drowsy} = require '../backbone.drowsy'
    {Wakeful} = require '../wakeful'
    should = require('chai').should()
    WebSocket = require 'ws'

DROWSY_URL = "http://localhost:9292"
WAKEFUL_URL = "ws://localhost:7777"
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
    @timeout 4000
    @slow 1000

    before ->
        @server = new Drowsy.Server(DROWSY_URL)
        @db = @server.database(TEST_DB)
        class TestDoc extends @db.Document(TEST_COLLECTION)
        @TestDoc = TestDoc


    describe ".wake", ->
        it 'should enhance Drowsy.Document with wakeful functionality', ->
            doc = new @TestDoc()

            Wakeful.wake doc, WAKEFUL_URL

            doc.should.have.property 'connect'
            doc.connect.should.be.a 'function'

            doc.should.have.property 'disconnect'
            doc.disconnect.should.be.a 'function'

        describe "#connect", ->
            it 'should return a $.Deferred', ->
                doc = new @TestDoc()

                Wakeful.wake doc, WAKEFUL_URL

                conn = doc.connect()

                # doesn't work, do duck typing instead
                #conn.should.be.an.instanceOf $.Deferred
                conn.should.have.property 'resolve'
                conn.resolve.should.be.a 'function'
                conn.should.have.property 'reject'
                conn.reject.should.be.a 'function'

            it 'should trigger wakeful:open then wakeful:subscribed and then resolve', (done) ->
                doc = new @TestDoc()

                Wakeful.wake doc, WAKEFUL_URL

                conn = doc.connect()


                doc.socket.should.be.an.instanceOf WebSocket
                conn.state().should.equal 'pending'

                doc.on 'wakeful:open', ->
                    doc.socket.readyState.should.equal WebSocket.OPEN
                    conn.state().should.equal 'pending'
                    doc.on 'wakeful:subscribed', ->
                        conn.done ->
                            done()


        describe "#broadcast", ->
            # it "should notify when sent, and resolve when echoed", (done) ->
            #     doc = new @TestDoc()
            #     doc.save().done ->
            #         Wakeful.wake doc, WAKEFUL_URL
            #         doc.connect().done ->
            #             rand = Math.random()
            #             doc.set 'foo', rand

            #             sent = false

            #             bc = doc.broadcast 'update', doc.toJSON()
            #             bc.done ->
            #                 sent.should.be.true
            #                 done()
            #             bc.progress (note) ->
            #                 note.should.equal 'sent'
            #                 sent = true
            
            # it "should push onto the broadcastEchoQueue and then pop when echo received", (done) ->
            #     doc = new @TestDoc()
            #     doc.save().done ->
            #         Wakeful.wake doc, WAKEFUL_URL
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
                        console.log "Doc2 saved"
                        Wakeful.wake doc1, WAKEFUL_URL
                        Wakeful.wake doc2, WAKEFUL_URL
                        
                        conn1 = doc1.connect()
                        conn2 = doc2.connect()


                        sub1 = false
                        sub2 = false

                        doc1.on 'wakeful:subscribed', ->
                            sub1 = true
                        doc2.on 'wakeful:subscribed', ->
                            sub2 = true

                        conn1.state().should.equal 'pending'
                        conn2.state().should.equal 'pending'
                        
                        # when both have connected
                        $.when(conn1, conn2).done ->
                            conn1.state().should.equal 'resolved'
                            conn2.state().should.equal 'resolved'
                            sub1.should.be.true
                            sub2.should.be.true
                            console.log "Both open"
                            #console.log "Both Docs connected to WakefulWeasel"
                            rand = Math.random()
                            doc1.set 'foo', rand
                            doc1.get('foo').should.equal rand
                            doc2.has('foo').should.be.false

                            doc1.wid = 'doc1'
                            doc2.wid = 'doc2'

                            doc2.on 'change', ->
                                console.log "Doc2 changed"
                                doc2.get('foo').should.equal rand
                                done()

                            bc = doc1.broadcast 'update', doc1.toJSON(), doc1.wid
                            bc.progress (n) ->
                                console.log n

                        

    # describe ".sync", ->
    #     it "should cause an update to be synced across existing Drowsy.Documents", (done) ->
    #         doc1 = new @TestDoc()
    #         doc2 = new @TestDoc()

    #         doc1.save().done ->
    #             doc2.set '_id', doc1.id
    #             doc2.fetch().done ->
    #                 doc1.toJSON().should.eql doc2.toJSON()

    #                 Wakeful.wake doc1, WAKEFUL_URL
    #                 Wakeful.wake doc2, WAKEFUL_URL

    #                 conn1 = doc1.connect()
    #                 conn2 = doc2.connect()

    #                 # when both have connected
    #                 $.when(conn1, conn2).done ->
    #                     rand = Math.random()
    #                     doc1.set 'foo', rand
                        
    #                     doc2.on 'change', ->
    #                         doc2.get('foo').should.equal rand
    #                         done()

    #                     doc1.save()

                        








        