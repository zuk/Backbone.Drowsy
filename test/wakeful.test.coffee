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
    @timeout 3000
    @slow 1000

    before ->
        @server = new Drowsy.Server(DROWSY_URL)
        @db = @server.database(TEST_DB)
        class TestDoc extends @db.Document(TEST_COLLECTION)
        @TestDoc = TestDoc

    beforeEach ->
        Wakeful.websockets = {}
        Wakeful.subs = {}

    afterEach (done) ->
        dfs = []
        for url,ws of Wakeful.websockets
            dfs.push ws.ensuredClose()

        $.when.apply($, dfs).done ->
            done()


    describe ".wake", ->
        it 'should enhance Drowsy.Document with wakeful functionality', (done) ->
            doc = new @TestDoc()

            (Wakeful.wake doc, WAKEFUL_URL).done ->

                doc.should.have.property 'tunein'
                doc.tunein.should.be.a 'function'

                doc.should.have.property 'broadcast'
                doc.broadcast.should.be.a 'function'

                done()

        it 'should not create more than one WebSocket per ws URL', (done) ->
            doc1 = new @TestDoc()
            doc2 = new @TestDoc()
            doc3 = new @TestDoc()
            doc4 = new @TestDoc()

            df1 = Wakeful.wake doc1, WAKEFUL_URL
            df2 = Wakeful.wake doc2, WAKEFUL_URL
            df3 = Wakeful.wake doc3, WAKEFUL_URL

            $.when(df1,df2,df3).done ->
                Object.keys(Wakeful.websockets).length.should.equal 1

                doc1.websocket.should.equal doc2.websocket
                doc2.websocket.should.equal doc3.websocket

                df4 = Wakeful.wake doc4, WAKEFUL_URL+"/foo"

                df4.done ->
                    Object.keys(Wakeful.websockets).length.should.equal 2
                    doc1.websocket.should.not.equal doc4.websocket
                    done()

        it 'should create websockets that support ensuredClose()', (done) ->
            doc1 = new @TestDoc()
            doc2 = new @TestDoc()
            doc3 = new @TestDoc()

            df1 = Wakeful.wake doc1, WAKEFUL_URL
            df2 = Wakeful.wake doc2, WAKEFUL_URL
            df3 = Wakeful.wake doc3, WAKEFUL_URL

            $.when(df1,df2,df3).done ->
                doc1.websocket.should.have.property 'ensuredClose'
                doc2.websocket.should.have.property 'ensuredClose'
                doc3.websocket.should.have.property 'ensuredClose'

                doc1.websocket.ensuredClose().done ->
                    doc1.websocket.readyState.should.equal WebSocket.CLOSED
                    doc2.websocket.readyState.should.equal WebSocket.CLOSED
                    doc3.websocket.readyState.should.equal WebSocket.CLOSED
                    done()


        describe "#tunein", ->
            it 'should return a $.Deferred', (done) ->
                console.log 'should return a $.Deferred'
                doc = new @TestDoc()

                (Wakeful.wake doc, WAKEFUL_URL).done ->
                    sub = doc.tunein()

                    # duck typing check
                    sub.should.have.property 'resolve'
                    sub.resolve.should.be.a 'function'

                    sub.done -> done()

            it 'should make sure a WebSocket is open', (done) ->
                console.log 'should make sure a WebSocket is open'
                doc = new @TestDoc()

                Wakeful.wake doc, WAKEFUL_URL
                
                sub = doc.tunein()

                sub.always ->
                    doc.websocket.readyState.should.equal WebSocket.OPEN
                    done()

            it 'should register a subscription with Wakeful', (done) ->
                console.log 'should register a subscription with Wakeful'
                doc = new @TestDoc()

                Wakeful.wake doc, WAKEFUL_URL
                
                sub = doc.tunein()

                sub.done ->
                    Wakeful.subs[doc.resourceUrl()].length.should.equal 1
                    Wakeful.subs[doc.resourceUrl()].should.include doc
                    done()

            it 'should allow multiple subscriptions for the same URL', (done) ->
                docA = new @TestDoc()
                docB = new @TestDoc()
                docB.set('_id', docA.id)

                Wakeful.wake docA, WAKEFUL_URL
                Wakeful.wake docB, WAKEFUL_URL 

                subA = docA.tunein()
                subB = docB.tunein()
                console.log "A",docA.resourceUrl()
                console.log "B",docB.resourceUrl()

                subA.done -> console.log "A", "DONE"
                subB.done -> console.log "B", "DONE"

                $.when(subA, subB).done ->
                    Wakeful.subs[docA.resourceUrl()].length is 2
                    done()

            it 'should trigger wakeful:subscription and then resolve', (done) ->
                doc1 = new @TestDoc()
                doc2 = new @TestDoc()

                Wakeful.wake doc1, WAKEFUL_URL
                Wakeful.wake doc2, WAKEFUL_URL 

                subA = doc1.tunein()
                subB = doc2.tunein()
                console.log "A",doc1.resourceUrl()
                console.log "B",doc2.resourceUrl()

                subA.done -> console.log "A", "DONE"
                subB.done -> console.log "B", "DONE"

                $.when(subA, subB).done ->
                    Wakeful.subs[doc1.resourceUrl()].length is 2
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

                        doc1.on 'wakeful:tuneind', ->
                            sub1 = true
                        doc2.on 'wakeful:tuneind', ->
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

                        








        