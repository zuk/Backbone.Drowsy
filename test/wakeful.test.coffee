if window?
    # we're running in a browser
    $ = window.$
    _ = window._
    Backbone = window.Backbone
    Drowsy = window.Drowsy
    Wakeful = window.Wakeful
else
    # we're running in node
    $ = require 'jquery'
    _ = require 'underscore'
    Backbone = require 'backbone'
    Backbone.$ = $
    {Drowsy} = require '../backbone.drowsy'
    Wakeful = require '../wakeful'
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
    describe ".wake", ->
        beforeEach ->
            @server = new Drowsy.Server(DROWSY_URL)
            @db = @server.database(TEST_DB)
            class TestDoc extends @db.Document(TEST_COLLECTION)
            @TestDoc = TestDoc

        it 'should enhance Drowsy.Document with wakeful functionality', ->
            doc = new @TestDoc()

            Wakeful.wake doc, WAKEFUL_URL

            doc.should.have.property 'connect'
            doc.connect.should.be.a 'function'

            doc.should.have.property 'disconnect'
            doc.disconnect.should.be.a 'function'

        it 'should allow the Drowsy.Document to connect to WakefulWeasel', (done) ->
            doc = new @TestDoc()

            Wakeful.wake doc, WAKEFUL_URL

            doc.connect()

            doc.socket.should.be.an.instanceOf WebSocket

            doc.on 'wakeful:connected', ->
                doc.socket.readyState.should.equal WebSocket.OPEN
                done()

        describe "#broadcast", ->
            it "should send an update from one Drowsy.Document to another Drowsy.Document with the same URL", (done) ->
                doc1 = new @TestDoc()
                doc2 = new @TestDoc()

                doc1.save {},
                    success: ->
                        doc2.set('_id', doc1.id)
                        doc2.url().should.equal doc1.url()
                        console.log "Both Docs assigned url the same URL", doc1.url()
                        doc2.save {},
                            success: ->
                                console.log "Both Docs saved"

                                Wakeful.wake doc1, WAKEFUL_URL
                                Wakeful.wake doc2, WAKEFUL_URL

                                df1 = $.Deferred()
                                df2 = $.Deferred()
                                doc1.on 'wakeful:connected', -> df1.resolve()
                                doc2.on 'wakeful:connected', -> df2.resolve()

                                $.when(df1, df2).then ->
                                    console.log "Both Docs connected to WakefulWeasel"
                                    rand = Math.random()
                                    doc1.set 'foo', rand
                                    doc1.get('foo').should.equal rand
                                    doc2.has('foo').should.be.false

                                    doc2.on 'change', ->
                                        doc2.get('foo').should.equal rand
                                        done()

                                    doc1.broadcast 'update', doc1.toJSON()

                                doc1.connect()
                                doc2.connect()

    #describe ".sync", ->









        