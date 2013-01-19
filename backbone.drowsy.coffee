class Drowsy
    @generateMongoObjectId = ->
        base = 16
        randLength = 13
        time = Date.now().toString(base)
        rand = Math.ceil(Math.random() * (Math.pow(base, randLength) - 1)).toString(base)
        time + (Array(randLength + 1).join("0") + rand).slice(-randLength)

class Drowsy.Model extends Backbone.Model
    idAttribute: '_id'
    
    initialize = ->
        @set @idAttribute, generateMongoObjectId()  unless @get(@idAttribute)
        @set "created_at", Date()  unless @get("created_at")
    
    parse = (data) ->
        data._id = data._id.$oid
        parsedCreatedAt = new Date(data.created_at)  if data.created_at
        data.created_at = parsedCreatedAt  unless isNaN(parsedCreatedAt.getTime())
        data
        
class Drowsy.Collection extends Backbone.Collection
    model: Drowsy.Model