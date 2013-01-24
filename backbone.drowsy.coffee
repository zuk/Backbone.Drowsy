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

class Drowsy
    # FIXME: change this to better match the ObjectID spec: http://www.mongodb.org/display/DOCSDE/Object+IDs#ObjectIDs-BSONObjectIDSpecification
    #   ... also might have to move to Drowsy.Server to accomodate machineid (??)
    @generateMongoObjectId: ->
        base = 16
        randLength = 11

        time = (Date.now()*1000).toString(base)
        rand = Math.ceil(Math.random() * (Math.pow(base, randLength) - 1)).toString(base)
        time + (Array(randLength + 1).join("0") + rand).slice(-randLength)


class Drowsy.Server
    constructor: (url, options = {}) ->
        if typeof url is 'object'
            options = url
        else if typeof url is 'string'
            options.url = url

        @options = options

    url: ->
        @options.url.replace(/\/$/,'') # remove trailing /

    database: (dbName) =>
        new Drowsy.Database(@, dbName)

    databases: (after) =>
        Backbone.ajax
            url: @url()
            success: (data) =>
                dbs = []
                for dbName in data
                    if dbName.match Drowsy.Database.VALID_DB_RX
                        dbs.push @database(dbName)
                after dbs


class Drowsy.Database # this should be anonymous, but we're naming it for clarity in debugging
    @VALID_DB_RX: /[^\s\.\$\/\\\*]+/

    constructor: (server, dbName, options = {}) ->
        if typeof server is 'string'
            server = new Drowsy.Server(server)

        @server = server
        @name = dbName
        @options = options
        @url = server.url() + '/' + dbName


    collections: (after) =>
        db = @
        Backbone.ajax
            url: @url
            success: (data) =>
                colls = []
                for collName in data
                    c = new class extends db.Collection(collName)
                    colls.push c
                after(colls)

    createCollection: (collectionName, after) =>
        db = @
        Backbone.ajax
            url: db.url
            type: 'POST'
            data: {collection: collectionName}
            complete: (xhr, status) ->
                if after?
                    console.log xhr.status
                    if xhr.status is 304
                        after('already_exists')
                    else if xhr.status is 201
                        after('created')
                    else
                        after('failed', xhr.status)

    Document: (collectionName) =>
        db = @
        class extends Drowsy.Document # this should be anonymous, but we're naming it for clarity in debugging
            urlRoot: db.url + '/' + collectionName
            collectionName: collectionName

    Collection: (collectionName) =>
        db = @
        class extends Drowsy.Collection # this should be anonymous, but we're naming it for clarity in debugging
            url: db.url + '/' + collectionName
            name: collectionName

class Drowsy.Collection extends Backbone.Collection
    model: Drowsy.Document

class Drowsy.Document extends Backbone.Model
    idAttribute: '_id'
    
    initialize: ->
        @set @idAttribute, Drowsy.generateMongoObjectId()  unless @get(@idAttribute)
        #@set "created_at", Date()  unless @get("created_at")
    
    parse: (data) ->
        data._id = data._id.$oid

        # convert all { $data: "..." } to Date() object
        parsed = @parseObjectRecursively data, @jsonToDate

        parsed

    toJSON: (options = {}) ->
        data = super(options)

        parsed = @parseObjectRecursively data, @dateToJson

        parsed

    ### 
    private 
    ###

    # recursively parses all values in the object using the given parser
    parseObjectRecursively: (obj, parser) ->
        out = {}
        for key,val of obj
            out[key] = parser(val)
            if typeof out[key] is 'object' and 
                    # check that this is an object that can be iterated over (as opposed to something like a Date)
                    Object.keys(out[key]).length > 0 
                out[key] = @parseObjectRecursively out[key], parser
        
        out

    jsonToDate: (val) ->
        if val.$date?
            date = new Date(val.$date)
            if isNaN date.getTime()
                val.$invalid = true
                val
            else
                date
        else
            val

    dateToJson: (val) ->
        if val instanceof Date
            { "$date": val.toJSON() }
        else
            val




root = exports ? this
root.Drowsy = Drowsy