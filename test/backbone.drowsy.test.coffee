if window?
    # we're running in a browser
    $ = window.$
    _ = window._
    should = window.should
    Backbone = window.Backbone
    Drowsy = window.Drowsy
    DROWSY_URL = window.DROWSY_URL
    WEASEL_URL = window.WEASEL_URL
else
    # we're running in node
    $ = require 'jquery'
    _ = require 'underscore'
    Backbone = require 'backbone'
    Backbone.$ = $
    should = require('chai').should()
    {Drowsy} = require '../backbone.drowsy'
    DROWSY_URL = process.env.DROWSY_URL
    WEASEL_URL = process.env.WEASEL_URL

###
NOTE: These tests are done against a live DrowsyDromedary instance!
###

DROWSY_URL = "http://localhost:9292/" unless DROWSY_URL?
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


unless DROWSY_URL?
    console.error("DROWSY_URL must point to a DrowsyDromedary server!")

describe 'Drowsy', ->
    @timeout(5000)

    before (done) ->
        createTestCollection = =>
            db = @server.database(TEST_DB)
            db.collections().done (colls) =>
                if TEST_COLLECTION in _.pluck(colls, 'name')
                    done()
                else
                    db.createCollection(TEST_COLLECTION).done ->
                        done()

        # ensure that the test database and collection exists
        @server = new Drowsy.Server(DROWSY_URL)
        @server.databases().done (dbs) =>
            if TEST_DB in _.pluck(dbs, 'name')
                createTestCollection()
            else
                @server.createDatabase(TEST_DB).done createTestCollection



    describe ".generateMongoObjectId", ->
        it "should generate a 24-character hex string", ->
            id = Drowsy.generateMongoObjectId()
            id.should.match /^[0-9a-f]{24}$/

    describe 'Drowsy.Server', ->
        describe '#url', ->
            it "should strip the trailing slash off the URL", ->
                @server.url().slice(-1).should.not.equal '/'

        describe '#database', ->
            it "should return a new Drowsy.Database object with the given name", ->
                db = @server.database(TEST_DB)

                db.should.be.an.instanceOf Drowsy.Database
                
                db.name.should.equal TEST_DB
                db.url.should.match new RegExp("^#{DROWSY_URL}")
                db.url.should.match new RegExp("#{TEST_DB}$")

        describe '#databases', ->
            it "should retrieve a list of all databases from the remote server as Drowsy.Database objects", (done) ->
                @server.databases (dbs) ->
                    dbs[0].should.be.an.instanceOf Drowsy.Database
                    dbs[0].name.should.not.be.empty
                    _.pluck(dbs, 'name').should.include TEST_DB
                    done()

        #TODO: test '#createDatabase'

    describe 'Drowsy.Database', ->
        before ->
           @server = new Drowsy.Server(DROWSY_URL)
           @db = new Drowsy.Database(@server, TEST_DB)

        describe 'constructor', ->
            it "should assign a url based on the given server and dbName", ->
                db = new Drowsy.Database @server, TEST_DB
                db.url.should.equal DROWSY_URL.replace(/\/$/,'') + "/" + TEST_DB

            it "should be able to take a url as first argument", ->
                (=> db = new Drowsy.Database DROWSY_URL, TEST_DB).should.not.throw(/url/)

            it "should be able to take a Drowsy.Server instance as the first argument", ->
                (=> db = new Drowsy.Database @server, TEST_DB ).should.not.throw(/url/)

        describe '#collections', ->
            it "should retrieve a list of Drowsy.Collection instances", (done) ->
                @db.collections (colls) ->
                    (colls.length > 0).should.equal true
                    _.each colls, (coll) ->
                        coll.should.be.an.instanceOf Drowsy.Collection
                    _.pluck(colls, 'name').should.include TEST_COLLECTION
                    done()


            it "should instantiate Drowsy.Collection instances with valid urls and collectionNames", (done) ->
                @db.collections (colls) ->
                    _.each colls, (coll) ->
                        #console.log coll.url
                        coll.url.should.not.match /undefined/
                        coll.name.should.exist
                    done()

        describe '#createCollection', ->
            it "should create the given collection in this database", (done) ->
                @db.createCollection TEST_COLLECTION, (result) ->
                    result.should.match /created|already_exists/
                    done()

            it "should return a deferred and resolve to 'created' or 'already_exists'", (done) ->
                @db.createCollection(TEST_COLLECTION).always (result, xhr) ->
                    result.should.match /created|already_exists/
                    @state().should.equal 'resolved'
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
                doc.url().should.match new RegExp("^" + DROWSY_URL.replace(/\/$/,'') + "/" + TEST_DB + "/" + TEST_COLLECTION + "/" + "[0-9a-f]+" + "$")

        describe "#Collection", ->
            it "should return a Drowsy.Collection class with the given collectionName", ->
                class TestCollection extends @db.Collection(TEST_COLLECTION)

                coll = new TestCollection()
                coll.name.should.equal TEST_COLLECTION
                
            it "should return a Drowsy.Collection class with a valid URL", ->
                class TestCollection extends @db.Collection(TEST_COLLECTION)

                coll = new TestCollection()
                console.log coll.url
                coll.url.should.match new RegExp("^" + DROWSY_URL.replace(/\/$/,'') + "/" + TEST_DB + "/" + TEST_COLLECTION + "$")

    describe 'Drowsy.Document', ->
        describe "#dirtyAttributes", ->
            it "should accumulate until the document is saved", (done) ->
                class MyDoc extends @db.Document(TEST_COLLECTION)

                doc = new MyDoc()
                
                doc.set('_id', "000000000000000000000001")
                
                doc.dirtyAttributes().should.eql {_id: "000000000000000000000001"}

                doc.set('foo', "bar")
                doc.dirtyAttributes().should.eql {_id: "000000000000000000000001", foo: "bar"}

                doc.on 'sync', ->
                    doc.dirtyAttributes().should.eql {}
                    done()

                doc.save()

            describe "#dirtyAttributes", ->
            it "should be per-object", (done) ->
                class MyDoc extends @db.Document(TEST_COLLECTION)

                doc1 = new MyDoc()
                doc2 = new MyDoc()
                
                doc1.set('_id', "000000000000000000000001")
                doc2.set('_id', "000000000000000000000002")
                
                doc1.dirtyAttributes().should.eql {_id: "000000000000000000000001"}
                doc2.dirtyAttributes().should.eql {_id: "000000000000000000000002"}

                doc1.set('foo', "bar")
                doc1.dirtyAttributes().should.eql {_id: "000000000000000000000001", foo: "bar"}

                doc2.set('bleh', "blarg")
                doc2.dirtyAttributes().should.eql {_id: "000000000000000000000002", bleh: "blarg"}

                doc1.on 'sync', ->
                    doc1.dirtyAttributes().should.eql {}
                    doc2.dirtyAttributes().should.eql {_id: "000000000000000000000002", bleh: "blarg"}

                    doc2.on 'sync', ->
                        doc1.dirtyAttributes().should.eql {}
                        doc2.dirtyAttributes().should.eql {}
                        done()

                    doc2.save()

                doc1.save()

        describe "#parse", ->
            it "should deal with ObjectID encoded as {$oid: '...'}", ->
                data = JSON.parse '{"_id": {"$oid": "50f7875a1b85e10000000003"}, "foo": "bar"}'

                doc = new Drowsy.Document()
                parsed = doc.parse(data)

                parsed._id.should.equal "50f7875a1b85e10000000003"
                parsed.foo.should.equal "bar"

            it "should deal with ObjectID encoded as a plain string (without $oid)", ->
                data = JSON.parse '{"_id": "50f7875a1b85e10000000003", "foo": "bar"}'

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

            it "should deal with ISODates encoded as {$date: '...'} in an Array", ->
                data = JSON.parse '{
                        "_id": {"$oid": "50f7875a1b85e10000000003"}, 
                        "array_of_dates": [{ "$date": "2013-01-17T05:08:42.537Z" }, { "$date": "2013-01-17T05:08:42.537Z" }],
                        "array_of_objs_with_dates": [{"foo": { "$date": "2013-01-17T05:08:42.537Z" }}, {"foo": { "$date": "2013-01-17T05:08:42.537Z" }}]
                    }'

                doc = new Drowsy.Document()
                parsed = doc.parse(data)

                theDate = new Date("2013-01-17T05:08:42.537Z")

                parsed._id.should.equal "50f7875a1b85e10000000003"
                parsed.array_of_dates[0].should.eql theDate
                parsed.array_of_dates[1].should.eql theDate
                parsed.array_of_objs_with_dates[0].foo.should.eql theDate
                parsed.array_of_objs_with_dates[1].foo.should.eql theDate

            it "should parse an array value as an array rather than an object", ->
                data = JSON.parse '{
                        "_id": {"$oid": "50f7875a1b85e10000000003"}, 
                        "foo": "bar",
                        "arr": [
                            {"foo": "bar"},
                            {"joo": "gar"},
                            "foobar"
                        ],
                        "arr2": ["apple", "banana", 1, 2],
                        "obj": {
                            "0": {"foo": "bar"},
                            "1": {"joo": "gar"}
                        }
                    }'

                doc = new Drowsy.Document()
                parsed = doc.parse(data)
                
                parsed.arr.should.be.an 'array'
                parsed.arr[1].joo.should.equal 'gar'

                parsed.arr[2].should.equal 'foobar'
                parsed.arr2[1].should.equal 'banana'

                parsed.obj.should.be.an 'object'
                parsed.obj[1].joo.should.equal 'gar'


            it "should parse an object with a keys with null values", ->
                data = JSON.parse '{
                        "_id": {"$oid": "50f7875a1b85e10000000003"}, 
                        "null1": null,
                        "obj": {
                            "foo": {"foo": "bar"},
                            "bar": {"null2": null}
                        }
                    }'

                doc = new Drowsy.Document()
                parsed = doc.parse(data)

                should.not.exist parsed.null1
                should.not.exist parsed.obj.bar.null2

            # extreme edge case
            it "should parse an empty collection", ->
                data = JSON.parse '[]'

                coll = new Drowsy.Collection()
                parsed = coll.parse(data)

                


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

            it "should convert Dates to {$date: '...'} when they're inside arrays", ->
                doc = new Drowsy.Document()
                theDate = new Date("2013-01-24T02:01:35.151Z")
                doc.set('array_of_dates', [theDate, theDate])
                doc.set('array_of_objs_with_dates', [{foo: theDate}, {foo: theDate}])

                json = doc.toJSON()
                json.array_of_dates[0].should.eql "$date": "2013-01-24T02:01:35.151Z"
                json.array_of_dates[1].should.eql "$date": "2013-01-24T02:01:35.151Z"
                json.array_of_objs_with_dates[0].should.eql foo: {"$date": "2013-01-24T02:01:35.151Z"}
                json.array_of_objs_with_dates[1].should.eql foo: {"$date": "2013-01-24T02:01:35.151Z"}

            it "should convert arrays of literals as arrays of literals", ->
                doc = new Drowsy.Document()
                doc.set('array_of_strings', ["abc", "def", "ghi"])
                doc.set('array_of_integers', [1, 2, 3, 4])
                doc.set('mixed_array', ["abc", 42, {"foo": "bar"}])

                json = doc.toJSON()
                json.array_of_strings[0].should.eql "abc"
                json.array_of_strings[2].should.eql "ghi"
                json.array_of_integers[0].should.eql 1
                json.array_of_integers[3].should.eql 4
                json.mixed_array[0].should.eql "abc"
                json.mixed_array[1].should.eql 42
                json.mixed_array[2].should.eql "foo": "bar"

        
        describe "#save", ->
            it "should upsert using a client-side generated ObjectID", (done) ->
                class MyDoc extends @db.Document(TEST_COLLECTION)

                doc = new MyDoc()

                console.log "Doc URL is:", doc.url()

                #doc.on 'all', (args...) -> console.log(args)
                doc.save()
                    .fail (data, xhr) ->
                        console.log xhr
                        console.log "Doc save error:",JSON.parse(xhr.responseText).error
                    .always (xhr, status) ->
                        status.should.equal "success"
                        done()

    describe 'Drowsy.Collection', ->
        # TODO: write some specs

