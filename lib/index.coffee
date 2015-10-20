Transform = require 'readable-stream/transform'

class ConcurrentTransform extends Transform
  _isDone: false
  concurrentJobs: 0
  maxConcurrentJobs: 10

  constructor: (options) ->
    if options?.maxConcurrentJobs?
      @maxConcurrentJobs = options.maxConcurrentJobs
    super(options)
    # we can't replace the listener that was added by the constructor, so we
    # remove it entirely and add our own
    @removeListener 'prefinish', @listeners('prefinish')[0]
    @once 'prefinish', =>
      @_isDone = true
      if @concurrentJobs is 0
        @_prefinish()

  _prefinish: =>
    if typeof @_flush is 'function'
      @_flush (err) =>
        done this, err
        return
    else
      done this
    return

  # Override `Transform._read()` so we can handle all interaction with the
  # '_transform' function
  _read: =>
    ts = @_transformState

    if ts.writechunk isnt null and ts.writecb and not ts.transforming
      ts.transforming = true
      @concurrentJobs += 1
      deferCb = @concurrentJobs >= @maxConcurrentJobs
      @_transform(ts.writechunk, ts.writeencoding, (err, res) =>
        @concurrentJobs -= 1
        if err then return @emit('error', err)
        if res? then @push res
        if deferCb
          ts.afterTransform()
        if @_isDone and @concurrentJobs is 0
          @_prefinish()
        return
      )
      if not deferCb
        ts.afterTransform()
        return
    else
      # mark that we need a transform, so that any data that comes in
      # will get processed, now that we've asked for it.
      ts.needTransform = true
    return

# this is a copy of the done function from the readable-stream module, just
# rewritten in CoffeeScript
done = (stream, err) ->
  if err then return stream.emit('error', err)
  # if there's nothing in the write buffer, then that means that nothing more
  # will ever be provided
  ws = stream._writableState
  ts = stream._transformState
  if ws.length
    throw new Error('calling transform done when ws.length != 0')
  if ts.transforming
    throw new Error('calling transform done when still transforming')
  stream.push null

module.exports = ConcurrentTransform
