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
    {Wakeful} = require '../backbone.wakeful'

DROWSY_URL = "http://localhost:9393/"
WAKEFUL_URL = "ws://localhost"
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
        before ->
            @server = new Drowsy.Server(DROWSY_URL)
            @db = drowsyServer.database(TEST_DB)

        it 'should enhance Drowsy.Document with wakeful functionality', ->
            class TestDoc extends @db.Document

            doc = new TestDoc()

            Wakeful.wake doc

            doc.should.have.property 'connect'
            doc.connect.should.be.a 'function'

            doc.should.have.property 'disconnect'
            doc.disconnect.should.be.a 'function'

        it 'should allow the Drowsy.Document to connect to WakefulWeasel', ->
            class TestDoc extends @db.Document

            doc = new TestDoc()

            Wakeful.wake doc

            doc.connect()

            doc.socket.should.be.an.instanceOf WebSocket
            



        