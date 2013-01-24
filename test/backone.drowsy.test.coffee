if window?
    # we're running in a browser
    $ = window.$
    _ = window._
    Backbone = window.Backbone
else
    # we're running in node
    $ = require('jquery');
    _ = require 'underscore'
    Backbone = require 'backbone'
    Backbone.$ = $
    {Drowsy} = require '../backbone.drowsy'

###
NOTE: These tests are done against a live DrowsyDromedary instance!
###

#TEST_URL = "http://drowsy.badger.encorelab.org/"
TEST_URL = "http://localhost:9393/"
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


unless TEST_URL?
    console.error("TEST_URL must point to a DrowsyDromedary server!")

describe 'Drowsy', ->
    describe 'Drowsy.Server', ->
        before ->
           @server = new Drowsy.Server(TEST_URL)

        describe '#url', ->
            it "should strip the trailing slash off the URL", ->
                @server.url().slice(-1).should.not.equal '/'

        describe '#database', ->
            it "should instantiate a new Drowsy.Database with the given name", ->
                db = @server.database(TEST_DB)

                db.should.be.an.instanceOf Drowsy.Database
                
                db.name.should.equal TEST_DB
                db.url.should.match new RegExp("^#{TEST_URL}")
                db.url.should.match new RegExp("#{TEST_DB}$")

        describe '#databases', ->
            it "should retrieve and instanitate a list of all databases on the remote server", (done) ->
                @server.databases (dbs) ->
                    dbs[0].should.be.an.instanceOf Drowsy.Database
                    dbs[0].name.should.not.be.empty
                    done()

    describe 'Drowsy.Database', ->
        before ->
           @server = new Drowsy.Server(TEST_URL)
           @db = new Drowsy.Database(@server, TEST_DB)

        describe 'constructor', ->
            it "should assign a url based on the given server and dbName", ->
                db = new Drowsy.Database @server, TEST_DB
                db.url.should.equal TEST_URL.replace(/\/$/,'') + "/" + TEST_DB

            it "should be able to take a url as first argument", ->
                (=> db = new Drowsy.Database TEST_URL, TEST_DB).should.not.throw(/url/)

            it "should be able to take a Drowsy.Server instance as the first argument", ->
                (=> db = new Drowsy.Database @server, TEST_DB ).should.not.throw(/url/)

        describe '#collections', ->
            it "should retrieve a list of Drowsy.Collection instances", (done) ->
                @db.collections (colls) ->
                    (colls.length > 0).should.equal true
                    _.each colls, (coll) ->
                        coll.should.be.an.instanceOf Drowsy.Collection
                    done()

            it "should instantiate Drowsy.Collection instances with valid urls and collectionNames", (done) ->
                @db.collections (colls) ->
                    _.each colls, (coll) ->
                        console.log coll.url
                        coll.url.should.not.match /undefined/
                        coll.name.should.exist
                    done()

        describe "#Document", ->
            it "should return a Drowsy.Document class with the given collectionName", ->
                class TestDocument extends @db.Document(TEST_COLLECTION)

                doc = new TestDocument()
                doc.collectionName.should.equal TEST_COLLECTION
                
            it "should return a Drowsy.Document class with a valid URL", ->
                class TestDocument extends @db.Document(TEST_COLLECTION)

                doc = new TestDocument()
                console.log doc.url()
                doc.url().should.match new RegExp("^" + TEST_URL.replace(/\/$/,'') + "/" + TEST_DB + "/" + TEST_COLLECTION + "/" + "[0-9a-f]+" + "$")

        describe "#Collection", ->
            it "should return a Drowsy.Collection class with the given collectionName", ->
                class TestCollection extends @db.Collection(TEST_COLLECTION)

                coll = new TestCollection()
                coll.name.should.equal TEST_COLLECTION
                
            it "should return a Drowsy.Collection class with a valid URL", ->
                class TestCollection extends @db.Collection(TEST_COLLECTION)

                coll = new TestCollection()
                console.log coll.url
                coll.url.should.match new RegExp("^" + TEST_URL.replace(/\/$/,'') + "/" + TEST_DB + "/" + TEST_COLLECTION + "$")

    describe 'Drowsy.Document', ->
        describe "#parse", ->
            it "should deal with ObjectID encoded as {$oid: '...'}", ->
                data = JSON.parse '{"_id": {"$oid": "50f7875a1b85e10000000003"}, "foo": "bar"}'

                doc = new Drowsy.Document()
                parsed = doc.parse(data)

                parsed._id.should.equal "50f7875a1b85e10000000003"
                parsed.foo.should.equal "bar"

            it "should deal with ISODates encoded as {$date: '...'}", ->
                data = JSON.parse '{
                        "_id": {"$oid": "50f7875a1b85e10000000003"}, 
                        "foo": "bar",
                        "date1": { "$date": "2013-01-17T05:08:42.537Z" },
                        "meh": {
                            "date2": { "$date": "2013-01-24T02:01:35.151Z"}, 
                            "joo": 55555
                        }
                    }'

                doc = new Drowsy.Document()
                parsed = doc.parse(data)

                parsed._id.should.equal "50f7875a1b85e10000000003"
                parsed.foo.should.equal "bar"
                (parsed.date1 instanceof Date).should.be.true
                parsed.date1.getTime().should.equal (new Date("2013-01-17T05:08:42.537Z")).getTime()
                (parsed.date1 instanceof Date).should.be.true
                parsed.meh.date2.getTime().should.equal (new Date("2013-01-24T02:01:35.151Z")).getTime()

        describe "#toJSON", ->
            it "should NOT convert _id to {$oid: '...'}", -> # DrowsyDromedary doesn't expect _id to be specially formatted on input
                doc = new Drowsy.Document()
                doc.set('_id', "000000000000000000000001")
                doc.id.should.equal "000000000000000000000001"

                json = doc.toJSON()
                
                json._id.should.equal "000000000000000000000001"


            it "should convert Dates to {$date: '...'}", ->
                doc = new Drowsy.Document()
                doc.set('foo', new Date("2013-01-17T05:08:42.537Z"))
                doc.set('faa', {'another': new Date("2013-01-24T02:01:35.151Z")})
                doc.set('fee', 'non-date value')
                doc.set('boo', {})

                json = doc.toJSON()
                json.foo.should.eql {"$date": "2013-01-17T05:08:42.537Z"}
                json.faa.another.should.eql {"$date": "2013-01-24T02:01:35.151Z"}
                json.fee.should.equal "non-date value"
                json.boo.should.eql {}

    describe 'Drowsy.Collection', ->
        # TODO: write some specs
