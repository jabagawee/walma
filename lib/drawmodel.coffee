
_  = require 'underscore'

{GridStore} = require "mongodb"

class exports.Drawing

  Drawing.collection = null
  Drawing.db = null

  cacheInterval: 10

  constructor: (@name) ->
    throw "Collection must be set" unless Drawing.collection
    @clients = {}
    @drawsAfterLastCache = 0

  addDraw: (draw, client, cb) ->
    Drawing.collection.update name: @name,
      $push: history: draw
    , (err, coll) =>
      return cb? err if err
      cb? null
      @drawsAfterLastCache += 1
      if not @fethingBitmap and @drawsAfterLastCache > @cacheInterval
        console.log "Asking for bitmap from #{ client.id }"
        @fethingBitmap = true

        client.fetchBitmap (err, bitmap) =>
          @fethingBitmap = false
          if err
            console.log "Could not get cache bitmap #{ err.message } #{ client.id }"
          else
            @saveCachePoint bitmap
            @drawsAfterLastCache = 0


  saveCachePoint: (bitmap, cb) ->
    filename = @name + bitmap.pos
    gs = new GridStore Drawing.db, filename, "w"
      content_type: "image/png"
      chunk_size: 1024*4

    gs.open (err) =>
      return cb? err if err
      gs.write bitmap.data, (err, result) =>
        return cb? err if err
        gs.close ->
          Drawing.collection.update name: @name,
            $push: cache: bitmap.pos
          , (err) ->
            cb? err, "wrote"



  getLatestCache: (cb) ->
    @fetch (err, doc) =>
      return cb? err if err
      lastPos = _.last doc.cache
      filename = @name + lastPos
      gs = new GridStore Drawing.db, filename, "r"
      gs.open (err) ->
        gs.close ->
        return cb? err if err
        cb null, gs




  addClient: (client, cb) ->
    @clients[client.id] = client

    client.join @name

    client.on "draw", (draw) =>
      @addDraw draw, client

    client.on "disconnect", =>
      delete @clients[client.id]

    client.on "bitmap", (bitmap) =>
      console.log "Client sending bitmap #{ bitmap } #{ client.id }"

    @fetch (err, doc) =>
      return cb? err if err
      client.startWith doc.history

  addCachePoint: (pos, bitmap) ->

  setDrawsAfterCachePoint: (history) ->
    return @drawsAfterLastCache in @drawsAfterLastCache

    i = 0
    for draw in history
      if draw.cache
        @drawsAfterLastCache = i
        i = 0

    @drawsAfterLastCache


  fetch: (cb) ->
    Drawing.collection.find(name: @name).nextObject (err, doc) =>
      return cb? err if err
      if doc
        @_doc = doc
        @setDrawsAfterCachePoint doc.history
        cb null, doc
      else
        Drawing.collection.insert
          name: @name
          history: []
          created: Date.now()
        ,
          safe: true
        , (err, docs) =>
          return cb? err if err
          @_doc = doc
          cb null, docs[0]


