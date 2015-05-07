Transform = require('../lib')

class PassThrough extends Transform
  _transform: (chunk, encoding, cb) ->
    cb(null, chunk)

module.exports = PassThrough
