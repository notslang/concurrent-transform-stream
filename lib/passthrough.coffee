Transform = require('../lib')

###*
 * This class is just for testing purposes... there shouldn't be any real
   usecase for a concurrent PassThrough transform.
###
class PassThrough extends Transform
  _transform: (chunk, encoding, cb) ->
    cb(null, chunk)

module.exports = PassThrough
