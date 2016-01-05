debug           = require('debug')('nanocyte-engine-worker:queue-worker')
Engine          = require '@octoblu/nanocyte-engine-simple'
Benchmark       = require 'simple-benchmark'

class QueueWorker
  constructor: ({@client,@timeout,@engineTimeout}) ->

  run: (callback) =>
    debug 'waiting for work'
    @client.brpop 'request:queue', @timeout, (error,result) =>
      return callback error if error?
      return callback() unless result?

      [queueName, requestStr] = result

      request = JSON.parse requestStr
      debug 'brpop', request.metadata
      @flowId = request.metadata.flowId # used to output flowId in case of timeout

      benchmark = new Benchmark label: 'queue-worker'
      engine = new Engine timeoutSeconds: @engineTimeout

      engine.run request, (error) =>
        debug "the worker thought we had an error", benchmark.toString() if error?
        debug "the worker noticed we ended", benchmark.toString()
        error.flowId = request.metadata?.flowId if error?
        callback error

module.exports = QueueWorker
