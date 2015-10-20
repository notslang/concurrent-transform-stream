should = require 'should'
Transform = require '../lib'
PassThrough = require '../lib/passthrough'
###
Transform = require 'readable-stream/transform'
PassThrough = require 'readable-stream/passthrough'
###

describe 'Stream PassThrough', ->
  it 'should support {objectMode: true}', (done) ->
    src = new PassThrough(objectMode: true)
    tx = new PassThrough(objectMode: true)
    dest = new PassThrough(objectMode: true)
    expect = [-1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
    results = []

    dest.on 'end', ->
      should.deepEqual(results, expect)
      done()

    dest.on 'data', (x) ->
      results.push x

    src.pipe(tx).pipe dest
    i = -1

    int = setInterval( ->
      if i > 10
        src.end()
        clearInterval int
      else
        src.write i++
      return
    )

describe 'Stream Transform', ->
  it 'should support {readableObjectMode: true}', (done) ->
    parser = new Transform(readableObjectMode: true)
    parser._readableState.objectMode.should.equal(true)
    parser._writableState.objectMode.should.equal(false)
    parser._readableState.highWaterMark.should.equal(16)
    parser._writableState.highWaterMark.should.equal(16 * 1024)

    parser._transform = (chunk, enc, callback) ->
      callback null, val: chunk[0]
      return

    parsed = undefined
    parser.on 'data', (obj) ->
      parsed = obj
      return

    parser.end new Buffer([42])

    parser.on 'end', ->
      parsed.val.should.equal(42)
      done()
      return

  it 'should support {writableObjectMode: true}', (done) ->
    serializer = new Transform(writableObjectMode: true)
    serializer._readableState.objectMode.should.equal(false)
    serializer._writableState.objectMode.should.equal(true)
    serializer._readableState.highWaterMark.should.equal(16 * 1024)
    serializer._writableState.highWaterMark.should.equal(16)

    serializer._transform = (obj, _, callback) ->
      callback null, new Buffer([obj.val])
      return

    serialized = undefined
    serializer.on 'data', (chunk) ->
      serialized = chunk
      return

    serializer.end val: 42

    serializer.on 'end', ->
      serialized[0].should.equal(42)
      done()
      return

  it 'should support {objectMode: true}', (done) ->
    stream = new Transform(objectMode: true)
    stream._readableState.objectMode.should.equal(true)
    stream._writableState.objectMode.should.equal(true)
    written = undefined
    read = undefined

    stream._write = (obj, _, cb) ->
      written = obj
      cb()
      return

    stream._read = ->

    stream.on 'data', (obj) ->
      read = obj
      return

    stream.push val: 1
    stream.end val: 2
    stream.on 'end', ->
      read.val.should.equal(1)
      written.val.should.equal(2)
      done()
      return

  it 'should support big packets', (done) ->
    passed = false

    class TestStream extends Transform
      _transform: (chunk, encoding, cb) ->
        if !passed
          # Char 'a' only exists in the last write
          passed = chunk.toString().indexOf('a') >= 0

        if passed
          # if it never gets to "a" then it will just time out
          done()

        cb()
        return

    s1 = new PassThrough()
    s2 = new PassThrough()
    s3 = new TestStream()
    s1.pipe s3
    # Don't let s2 auto close which may close s3
    s2.pipe s3, end: false

    # We must write a buffer larger than highWaterMark
    big = new Buffer(s1._writableState.highWaterMark + 1)
    big.fill 'x'

    # Since big is larger than highWaterMark, it will be buffered internally.
    s1.write(big).should.equal(false)

    # 'tiny' is small enough to pass through internal buffer.
    s2.write('tiny').should.equal(true)

    # Write some small data in next IO loop, which will never be written to s3
    # Because 'drain' event is not emitted from s1 and s1 is still paused
    setImmediate s1.write.bind(s1), 'later'

describe 'Stream2 Transform', ->
  it 'writable side consumption', (done) ->
    tx = new Transform(highWaterMark: 10)
    transformed = 0

    tx._transform = (chunk, encoding, cb) ->
      transformed += chunk.length
      tx.push chunk
      cb()
      return

    i = 1
    while i <= 10
      tx.write new Buffer(i)
      i++
    tx.end()
    should.equal tx._readableState.length, 10
    should.equal transformed, 10
    should.equal tx._transformState.writechunk.length, 5
    should.deepEqual tx._writableState.getBuffer().map((c) ->
      c.chunk.length
    ), [6, 7, 8, 9, 10]
    done()
    return

  it 'passthrough', (done) ->
    pt = new PassThrough()
    pt.write new Buffer('foog')
    pt.write new Buffer('bark')
    pt.write new Buffer('bazy')
    pt.write new Buffer('kuel')
    pt.end()
    should.equal pt.read(5).toString(), 'foogb'
    should.equal pt.read(5).toString(), 'arkba'
    should.equal pt.read(5).toString(), 'zykue'
    should.equal pt.read(5).toString(), 'l'
    done()
    return

  it 'object passthrough', (done) ->
    pt = new PassThrough(objectMode: true)
    pt.write 1
    pt.write true
    pt.write false
    pt.write 0
    pt.write 'foo'
    pt.write ''
    pt.write a: 'b'
    pt.end()
    should.equal pt.read(), 1
    should.equal pt.read(), true
    should.equal pt.read(), false
    should.equal pt.read(), 0
    should.equal pt.read(), 'foo'
    should.equal pt.read(), ''
    should.deepEqual pt.read(), a: 'b'
    done()
    return

  it 'simple transform', (done) ->
    pt = new Transform()

    pt._transform = (c, e, cb) ->
      ret = new Buffer(c.length)
      ret.fill 'x'
      pt.push ret
      cb()
      return

    pt.write new Buffer('foog')
    pt.write new Buffer('bark')
    pt.write new Buffer('bazy')
    pt.write new Buffer('kuel')
    pt.end()
    should.equal pt.read(5).toString(), 'xxxxx'
    should.equal pt.read(5).toString(), 'xxxxx'
    should.equal pt.read(5).toString(), 'xxxxx'
    should.equal pt.read(5).toString(), 'x'
    done()
    return

  it 'simple object transform', (done) ->
    pt = new Transform(objectMode: true)

    pt._transform = (c, e, cb) ->
      pt.push JSON.stringify(c)
      cb()
      return

    pt.write 1
    pt.write true
    pt.write false
    pt.write 0
    pt.write 'foo'
    pt.write ''
    pt.write a: 'b'
    pt.end()
    should.equal pt.read(), '1'
    should.equal pt.read(), 'true'
    should.equal pt.read(), 'false'
    should.equal pt.read(), '0'
    should.equal pt.read(), '"foo"'
    should.equal pt.read(), '""'
    should.equal pt.read(), '{"a":"b"}'
    done()
    return

  it.skip 'async passthrough', (done) ->
    pt = new Transform()

    pt._transform = (chunk, encoding, cb) ->
      setTimeout (->
        pt.push chunk
        cb()
        return
      ), 10
      return

    pt.write new Buffer('foog')
    pt.write new Buffer('bark')
    pt.write new Buffer('bazy')
    pt.write new Buffer('kuel')
    pt.end()
    pt.on 'finish', ->
      should.equal pt.read(5).toString(), 'foogb'
      should.equal pt.read(5).toString(), 'arkba'
      should.equal pt.read(5).toString(), 'zykue'
      should.equal pt.read(5).toString(), 'l'
      done()
      return
    return

  it.skip 'assymetric transform (expand)', (done) ->
    pt = new Transform()
    # emit each chunk 2 times.

    pt._transform = (chunk, encoding, cb) ->
      setTimeout (->
        pt.push chunk
        setTimeout (->
          pt.push chunk
          cb()
          return
        ), 10
        return
      ), 10
      return

    pt.write new Buffer('foog')
    pt.write new Buffer('bark')
    pt.write new Buffer('bazy')
    pt.write new Buffer('kuel')
    pt.end()
    pt.on 'finish', ->
      should.equal pt.read(5).toString(), 'foogf'
      should.equal pt.read(5).toString(), 'oogba'
      should.equal pt.read(5).toString(), 'rkbar'
      should.equal pt.read(5).toString(), 'kbazy'
      should.equal pt.read(5).toString(), 'bazyk'
      should.equal pt.read(5).toString(), 'uelku'
      should.equal pt.read(5).toString(), 'el'
      done()
      return
    return

  it.skip 'assymetric transform (compress)', (done) ->
    pt = new Transform()
    # each output is the first char of 3 consecutive chunks,
    # or whatever's left.
    pt.state = ''

    pt._transform = (chunk, encoding, cb) ->
      if !chunk
        chunk = ''
      s = chunk.toString()
      setTimeout (->
        @state += s.charAt(0)
        if @state.length == 3
          pt.push new Buffer(@state)
          @state = ''
        cb()
        return
      ).bind(this), 10
      return

    pt._flush = (cb) ->
      # just output whatever we have.
      pt.push new Buffer(@state)
      @state = ''
      cb()
      return

    pt.write new Buffer('aaaa')
    pt.write new Buffer('bbbb')
    pt.write new Buffer('cccc')
    pt.write new Buffer('dddd')
    pt.write new Buffer('eeee')
    pt.write new Buffer('aaaa')
    pt.write new Buffer('bbbb')
    pt.write new Buffer('cccc')
    pt.write new Buffer('dddd')
    pt.write new Buffer('eeee')
    pt.write new Buffer('aaaa')
    pt.write new Buffer('bbbb')
    pt.write new Buffer('cccc')
    pt.write new Buffer('dddd')
    pt.end()
    # 'abcdeabcdeabcd'
    pt.on 'finish', ->
      should.equal pt.read(5).toString(), 'abcde'
      should.equal pt.read(5).toString(), 'abcde'
      should.equal pt.read(5).toString(), 'abcd'
      done()
      return
    return
  # this tests for a stall when data is written to a full stream
  # that has empty transforms.

  it 'complex transform', (done) ->
    count = 0
    saved = null
    pt = new Transform(highWaterMark: 3)

    pt._transform = (c, e, cb) ->
      if count++ is 1
        saved = c
      else
        if saved
          pt.push saved
          saved = null
        pt.push c
      cb()
      return

    pt.once 'readable', ->
      process.nextTick ->
        pt.write new Buffer('d')
        pt.write new Buffer('ef'), ->
          pt.end()
          should.equal pt.read().toString(), 'abcdef'
          should.equal pt.read(), null
          done()
          return
        return
      return
    pt.write new Buffer('abc')
    return

  it 'passthrough event emission', (done) ->
    pt = new PassThrough()
    emits = 0
    pt.on 'readable', ->
      state = pt._readableState
      emits++
      return
    i = 0
    emits.should.equal(0)
    pt.write new Buffer('foog')
    pt.write new Buffer('bark')
    should.equal emits, 1
    should.equal pt.read(5).toString(), 'foogb'
    should.equal pt.read(5) + '', 'null'
    emits.should.equal(1)
    pt.write new Buffer('bazy')
    emits.should.equal(2)
    pt.write new Buffer('kuel')
    emits.should.equal(2)
    should.equal emits, 2
    should.equal pt.read(5).toString(), 'arkba'
    should.equal pt.read(5).toString(), 'zykue'
    should.equal pt.read(5), null
    emits.should.equal(2)
    pt.end()
    should.equal emits, 3
    should.equal pt.read(5).toString(), 'l'
    should.equal pt.read(5), null
    should.equal emits, 3
    done()
    return

  it 'passthrough event emission reordered', (done) ->
    pt = new PassThrough()
    emits = 0
    pt.on 'readable', ->
      emits++
      return
    emits.should.equal(0)
    pt.write new Buffer('foog')
    pt.write new Buffer('bark')
    should.equal emits, 1
    should.equal pt.read(5).toString(), 'foogb'
    should.equal pt.read(5), null
    emits.should.equal(1)
    pt.once 'readable', ->
      should.equal pt.read(5).toString(), 'arkba'
      should.equal pt.read(5), null
      emits.should.equal(2)
      pt.once 'readable', ->
        should.equal pt.read(5).toString(), 'zykue'
        should.equal pt.read(5), null
        pt.once 'readable', ->
          should.equal pt.read(5).toString(), 'l'
          should.equal pt.read(5), null
          should.equal emits, 4
          done()
          return
        pt.end()
        return
      pt.write new Buffer('kuel')
      return
    pt.write new Buffer('bazy')
    return

  it 'passthrough facaded', (done) ->
    pt = new PassThrough()
    datas = []
    pt.on 'data', (chunk) ->
      datas.push chunk.toString()
      return
    pt.on 'end', ->
      should.deepEqual datas, [
        'foog'
        'bark'
        'bazy'
        'kuel'
      ]
      done()
      return
    pt.write new Buffer('foog')
    setTimeout (->
      pt.write new Buffer('bark')
      setTimeout (->
        pt.write new Buffer('bazy')
        setTimeout (->
          pt.write new Buffer('kuel')
          setTimeout (->
            pt.end()
            return
          ), 10
          return
        ), 10
        return
      ), 10
      return
    ), 10
    return

  it 'object transform (json parse)', (done) ->
    jp = new Transform(objectMode: true)

    jp._transform = (data, encoding, cb) ->
      try
        jp.push JSON.parse(data)
        cb()
      catch err
        cb err
      return

    # anything except null/undefined is fine.
    # those are "magic" in the stream API, because they signal EOF.
    objects = [
      { foo: 'bar' }
      100
      'string'
      { nested: things: [
        { foo: 'bar' }
        100
        'string'
      ] }
    ]

    jp.on 'end', done

    objects.forEach (obj) ->
      jp.write JSON.stringify(obj), ->
        res = jp.read()
        should.deepEqual res, obj
        if obj is objects[-1..][0]
          # read one more time after last obj to get the 'end' event
          setImmediate -> jp.read()
      return

    jp.end()
    return

  it 'object transform (json stringify)', (done) ->
    js = new Transform(objectMode: true)
    js._transform = (data, encoding, cb) ->
      try
        js.push JSON.stringify(data)
        cb()
      catch err
        cb err
      return

    # anything except null/undefined is fine.
    # those are "magic" in the stream API, because they signal EOF.
    objects = [
      { foo: 'bar' }
      100
      'string'
      { nested: things: [
        { foo: 'bar' }
        100
        'string'
      ] }
    ]
    stringifiedObjects = []
    for obj in objects
      stringifiedObjects.push

    js.on 'end', done

    objects.forEach (obj) ->
      js.write obj, ->
        res = js.read()
        res.should.equal JSON.stringify(obj)
        if obj is objects[-1..][0]
          # read one more time after last obj to get the 'end' event
          setImmediate -> js.read()
      return

    js.end()
    return

  it 'should support concurrent pipes', (done) ->
    class Test extends Transform
      _transform: (chunk, encoding, cb) ->
        # set a timeout equal in duration to the number we got
        setTimeout(( ->
          cb(null, chunk)
        ), chunk)

    testStream = new Test(objectMode: true)
    destStream = new PassThrough(objectMode: true)

    output = []
    testStream.pipe(destStream)

    destStream.on('data', output.push.bind(output))
    destStream.on('finish', ->
      should.deepEqual(output, [
        100
        200
        300
        400
        500
        600
        700
        800
        900
        1000
      ])
      done()
    )

    # we output the smallest numbers first because they finish first. this test
    # would time out if it wasn't being done concurrently
    for i in [10...0]
      testStream.write i * 100

    testStream.end()

  it 'should be concurrent', (done) ->
    class Test extends Transform
      _transform: (chunk, encoding, cb) ->
        # set a timeout equal in duration to the number we got
        setTimeout(( ->
          cb(null, chunk)
        ), chunk)

    testStream = new Test(objectMode: true)

    output = []

    testStream.on('readable', ->
      output.push testStream.read()
    )
    testStream.on('end', ->
      should.deepEqual(output, [
        100
        200
        300
        400
        500
        600
        700
        800
        900
        1000
        null
      ])
      done()
    )

    # we output the smallest numbers first because they finish first. this test
    # would time out if it wasn't being done concurrently
    for i in [10...0]
      testStream.write i * 100

    testStream.end()
