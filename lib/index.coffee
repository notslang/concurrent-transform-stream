Duplex = require('readable-stream').Duplex
util = require('core-util-is')

class TransformState
  needTransform: false
  transforming: false
  writecb: null
  writechunk: null

  constructor: (@stream) ->

  afterTransform: (err, data) =>
    @transforming = false
    cb = @writecb
    if !cb
      return @stream.emit('error', new Error('no writecb in Transform class'))
    @writechunk = null
    @writecb = null
    if !util.isNullOrUndefined(data)
      @stream.push data
    if cb
      cb err
    rs = @stream._readableState
    rs.reading = false
    if rs.needReadable or rs.length < rs.highWaterMark
      @stream._read rs.highWaterMark
    return

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
      if util.isFunction(@_flush)
        @_flush (err) =>
          @_done(err)
          return
      else
        @_done()
      return
    return

  push: (chunk, encoding) =>
    @_transformState.needTransform = false
    super chunk, encoding

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
    ts = @_transformState
    ts.writecb = cb
    ts.writechunk = chunk
    ts.writeencoding = encoding
    if !ts.transforming
      rs = @_readableState
      if ts.needTransform or rs.needReadable or rs.length < rs.highWaterMark
        @_read rs.highWaterMark
    return

  # Doesn't matter what the args are here.
  # _transform does all the work.
  # That we got here means that the readable side wants more data.
  _read: (n) =>
    ts = @_transformState
    if !util.isNull(ts.writechunk) and ts.writecb and !ts.transforming
      ts.transforming = true
      @_transform ts.writechunk, ts.writeencoding, ts.afterTransform
    else
      # mark that we need a transform, so that any data that comes in
      # will get processed, now that we've asked for it.
      ts.needTransform = true
    return

  _done: (err) =>
    if err
      return @emit('error', err)
    # if there's nothing in the write buffer, then that means
    # that nothing more will ever be provided
    if @_writableState.length
      throw new Error('calling transform done when ws.length != 0')
    if @_transformState.transforming
      throw new Error('calling transform done when still transforming')
    @push null

module.exports = Transform
