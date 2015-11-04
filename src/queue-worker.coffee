debug           = require('debug')('nanocyte-engine-worker:queue-worker')
EngineInputNode = require '@octoblu/nanocyte-engine-simple/src/models/engine-input-node'
Benchmark       = require 'simple-benchmark'

class QueueWorker
  constructor: ({@client,@timeout}) ->

  run: (callback) =>
    @client.brpop 'request:queue', @timeout, (error,result) =>
      return callback error if error?
      return callback() unless result?

      [queueName, requestStr] = result

      request = JSON.parse requestStr
      debug 'brpop', JSON.stringify request.metadata

      benchmark = new Benchmark label: 'queue-worker'
      engineInput = new EngineInputNode
      inputStream = engineInput.message request

      inputStream.on 'data', =>

      inputStream.on 'end', =>
        debug "the worker noticed we ended", benchmark.toString()
        callback()
        
      inputStream.on 'error', =>
        debug "the worker thought we had an error", benchmark.toString()
        callback()

module.exports = QueueWorker
