if window?
    # we're running in a browser
    $ = window.$
    _ = window._
    Backbone = window.Backbone
    # not sure why, but sometimes we get "Backbone has no method 'ajax'" 
    # errors unless we do this first
    Backbone.ajax = $.ajax
else
    # we're running in node
    $ = require('jquery');
    _ = require 'underscore'
    Backbone = require 'backbone'
    Backbone.$ = $

    # for Drowsy.ObjectId
    crypto = require 'crypto'
    os = require 'os'

class Drowsy
    # TODO: should machineid be tied to Drowsy.Server rather than the client?
    @generateMongoObjectId: ->
        (new Drowsy.ObjectId()).toString()


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
        deferredFetch = $.Deferred()

        Backbone.ajax
            url: @url()
            dataType: 'json'
            success: (data) =>
                dbs = []
                for dbName in data
                    if dbName.match Drowsy.Database.VALID_DB_RX
                        dbs.push @database(dbName)
                deferredFetch.resolve(dbs)
                after(dbs) if after?
            error: (xhr, status) =>
                deferredFetch.reject(status, xhr)

        return deferredFetch

    createDatabase: (dbName, after) =>
        deferredCreate = $.Deferred()

        Backbone.ajax
            url: @url()
            type: 'POST'
            data: {db: dbName}
        .done (data, status, xhr) =>
            if status is 'success'
                deferredCreate.resolve('already_exists', xhr)
                after('already_exists') if after?
            else
                deferredCreate.resolve(status, xhr)
                after(status) if after?
        .fail (xhr, status) =>
            if xhr.status is 0 and xhr.responseText is ""
                # CORS requests come through as 
                deferredCreate.resolve('cors_mystery')
            deferredCreate.reject(xhr)
            after('failed') if after?

        return deferredCreate


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
        deferredFetch = $.Deferred()

        Backbone.ajax
            url: @url
            dataType: 'json'
        .done (data, status, xhr) =>
            colls = []
            for collName in data
                c = new class extends @Collection(collName)
                colls.push c
            deferredFetch.resolve(colls)
            after(colls) if after?
        .fail (xhr, status) =>
            deferredFetch.reject(xhr)
            after('failed') if after?

        return deferredFetch

    createCollection: (collectionName, after) =>
        deferredCreate = $.Deferred()
        
        Backbone.ajax
            url: @url
            type: 'POST'
            data: {collection: collectionName}
        .done (data, status, xhr) =>
            if status is 'success'
                deferredCreate.resolve('already_exists', xhr)
                after('already_exists') if after?
            else
                deferredCreate.resolve(status, xhr)
                after(status) if after?
        .fail (xhr, status) =>
            deferredCreate.reject(xhr)
            after('failed') if after?

        return deferredCreate

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
        @set @idAttribute, Drowsy.generateMongoObjectId() unless @has(@idAttribute)

    set: (key, val, options) ->
        res = super(key, val, options)
        @dirty ?= {}
        _.extend(@dirty, @changedAttributes())
        return res

    sync: (method, model, options) ->
        res = super(method, model, options)
        @dirty = {}
        return res

    reset: ->
        res = super()
        @dirty = {}
        return res

    fetch: (options = {}) ->
        # FIXME: couldn't think of a better way to do this... couldn't use deferred because
        #        .done() fires after 'sync' is triggered so it's too late
        #       ... also should we do this on 'always' or just 'success'?
        originalSuccess = options.success
        options.success = (doc, data, xhr) =>
            originalSuccess(doc,data,xhr) if originalSuccess?
            @dirty = {}

        res = super(options)
        return res

    dirtyAttributes: ->
        @dirty

    parse: (data) ->
        data._id = data._id.$oid ? data._id

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
        return null if obj is null

        out = parser obj

        # now see if we need recursive processing in case the parser didn't deal with it
        if _.isArray out
            for item,i in out
                out[i] = @parseObjectRecursively out[i], parser
        else if _.isObject(out) and
                # check that this is an object that can be iterated over (as opposed to something like a Date)
                Object.keys(out).length > 0
            for key,val of out
                out[key] = @parseObjectRecursively val, parser
        
        return out

    jsonToDate: (val) ->
        if val? and val.$date?
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

#
# Adapted from https://github.com/justaprogrammer/ObjectId.js
#
#*
#* Copyright (c) 2011 Justin Dearing (zippy1981@gmail.com)
#* Dual licensed under the MIT (http://www.opensource.org/licenses/mit-license.php)
#* and GPL (http://www.opensource.org/licenses/gpl-license.php) version 2 licenses.
#* This software is not distributed under version 3 or later of the GPL.
#*
#* Version 1.0.0
#*
#

###
Javascript class that mimics how WCF serializes a object of type MongoDB.Bson.ObjectId
and converts between that format and the standard 24 character representation.

TODO: move this stuff out into its own module...
###
class Drowsy.ObjectId
    @increment: 0

    constructor: (oid, machine, pid, incr) ->
        pid = pid ? Math.floor(Math.random() * (32767))
        machine = machine ? Math.floor(Math.random() * (16777216))
        
        if document?
            if localStorage?
                mongoMachineId = parseInt(localStorage["mongoMachineId"])
                machine = Math.floor(localStorage["mongoMachineId"])  if mongoMachineId >= 0 and mongoMachineId <= 16777215
            
                # Just always stick the value in.
                localStorage["mongoMachineId"] = machine
                document.cookie = "mongoMachineId=" + machine + ";expires=Tue, 19 Jan 2038 05:00:00 GMT"
            else
                cookieList = document.cookie.split("; ")
                for i of cookieList
                    cookie = cookieList[i].split("=")
                    if cookie[0] is "mongoMachineId" and cookie[1] >= 0 and cookie[1] <= 16777215
                        machine = cookie[1]
                        break
                document.cookie = "mongoMachineId=" + machine + ";expires=Tue, 19 Jan 2038 05:00:00 GMT"
        else
            mongoMachineId = crypto.createHash('md5').update(os.hostname()).digest('binary')

        if typeof oid is "object"
            @timestamp = oid.timestamp
            @machine = oid.machine
            @pid = oid.pid
            @increment = oid.increment
        else if typeof oid is "string" and oid.length is 24
            @timestamp = Number("0x" + oid.substr(0, 8))
            @machine = Number("0x" + oid.substr(8, 6))
            @pid = Number("0x" + oid.substr(14, 4))
            @increment = Number("0x" + oid.substr(18, 6))
        else if oid? and machine? and pid? and incr?
            @timestamp = oid
            @machine = machine
            @pid = pid
            @increment = incr
        else
            @timestamp = Math.floor(new Date().valueOf() / 1000)
            @machine = machine
            @pid = pid
            Drowsy.ObjectId.increment = 0  if Drowsy.ObjectId.increment > 0xffffff
            @increment = Drowsy.ObjectId.increment++

    getDate: ->
      new Date(@timestamp * 1000)


    ###
    Turns a WCF representation of a BSON ObjectId into a 24 character string representation.
    ###
    toString: ->
      timestamp = @timestamp.toString(16)
      machine = @machine.toString(16)
      pid = @pid.toString(16)
      increment = @increment.toString(16)
      return "00000000".substr(0, 6 - timestamp.length) + timestamp + 
        "000000".substr(0, 6 - machine.length) + machine + 
        "0000".substr(0, 4 - pid.length) + pid + 
        "000000".substr(0, 6 - increment.length) + increment


root = exports ? this
root.Drowsy = Drowsy