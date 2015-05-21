Duplex = require('readable-stream').Duplex
util = require 'core-util-is'

class TransformState
  ###*
   * The number of transforms that are active (haven't returned a value yet).
   * @type {Number}
  ###
  activeTransforms: 0

  maxActiveTransforms: 16

  ###*
   * If we have reached the highWaterMark, then this will hold the writeCb that
     we haven't called yet. There is only ever one writeCb waiting because we
     call all the other writeCbs immediately until we hit the highWaterMark
   * @type {Function}
  ###
  currentWriteCb: null

  ###*
   * Used to trigger the flush function when all the transforms are done.
   * @type {Function}
  ###
  drainCb: null

  jobBuffer: undefined

  lastStartedChunkId: 0

  lastOutputChunkId: 0

  constructor: (@stream) ->
    @jobBuffer = {}

  ###*
   * Calling the write callback is just done to get the next chunk from the
     writeableState. It doesn't contain the error or anything useful
  ###
  callWriteCb: =>
    rs = @stream._readableState
    if @currentWriteCb isnt null and
       @activeTransforms < @maxActiveTransforms and
       rs.length < rs.highWaterMark
      cb = @currentWriteCb
      delete @currentWriteCb
      cb.call(null) # pass no context

  afterTransform: (err, job) =>
    @activeTransforms--

    if err then @stream.emit('error', err)

    @jobBuffer[String(job.id)] = job.buffer
    @checkJobBuffer()
    @callWriteCb()

    rs = @stream._readableState
    rs.reading = false
    if rs.needReadable or rs.length < rs.highWaterMark
      @stream._read rs.highWaterMark
    return

  checkJobBuffer: =>
    while (finishedJob = @jobBuffer[String(@lastOutputChunkId)])?
      for [chunk, encoding] in finishedJob
        @stream.push(chunk, encoding)
      delete @jobBuffer[String(@lastOutputChunkId)]
      @lastOutputChunkId++

    if @drainCb? and Object.keys(@jobBuffer).length is 0 and @activeTransforms is 0
      @drainCb()
    return

  addJob: (chunk, encoding, cb) =>
    @activeTransforms++
    if @currentWriteCb?
      throw new Error('TransformState.currentWriteCb is already defined')
    else
      @currentWriteCb = cb
    new TransformJob(
      @lastStartedChunkId, @stream._transform, chunk, encoding, @afterTransform
    )
    @lastStartedChunkId++
    @callWriteCb()

class TransformJob
  index: null

  afterTransformCb: undefined

  ###*
   * Each job as a small internal buffer to hold the data it gets if
     preserveOrder is true
   * @type {Array}
  ###
  buffer: undefined

  constructor: (@id, transform, chunk, encoding, @afterTransformCb) ->
    @buffer = []
    process.nextTick(transform.bind(this, chunk, encoding, @afterTransform))

  afterTransform: (err, data) =>
    if data? then @push(data) # allow data to be returned via callback
    @afterTransformCb(err, this)

  push: (chunk, encoding) =>
    @buffer.push([chunk, encoding])

class Transform extends Duplex
  constructor: (options) ->
    if !(this instanceof Transform)
      return new Transform(options)

    super(options)

    @_transformState = new TransformState(this)

    # start out asking for a readable event once data is transformed.
    @_readableState.needReadable = true

    # we have implemented the _read method, and done the other things that
    # Readable wants before the first _read call, so unset the sync guard flag.
    @_readableState.sync = false

    # when the writable side finishes, then flush out anything remaining.
    @once 'prefinish', =>
      @_transformState.drainCb = =>
        if util.isFunction(@_flush)
          @_flush (err) =>
            @_done(err)
            return
        else
          @_done()
        return
      @_transformState.checkJobBuffer()
      return
    return

  # This is the part where you do stuff!
  # override this function in implementation classes.
  # 'chunk' is an input chunk.
  #
  # Call `push(newChunk)` to pass along transformed output
  # to the readable side.  You may call 'push' zero or more times.
  #
  # Call `cb(err)` when you are done with this chunk. If you pass
  # an error, then that'll put the hurt on the whole operation. If you
  # never call cb(), then you'll never get another chunk.
  _transform: (chunk, encoding, cb) ->
    throw new Error('not implemented')
    return

  _write: (chunk, encoding, cb) =>
    @_transformState.addJob(chunk, encoding, cb)

  # Doesn't matter what the args are here.
  # _transform does all the work.
  # That we got here means that the readable side wants more data.
  _read: (n) =>
    # we need _readableState.buffer to be emptied (by the read executing) before
    # we try calling the write callback, so we use nextTick.
    process.nextTick @_transformState.callWriteCb

  _done: (err) =>
    if err
      return @emit('error', err)
    # if there's nothing in the write buffer, then that means
    # that nothing more will ever be provided
    if @_writableState.length
      throw new Error('calling transform done when ws.length != 0')
    if @_transformState.activeTransforms > 0
      throw new Error('calling transform done when still transforming')
    @push null

module.exports = Transform
