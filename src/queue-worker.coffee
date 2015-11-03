debug           = require('debug')('nanocyte-engine-worker:queue-worker')
EngineInputNode = require '@octoblu/nanocyte-engine-simple/src/models/engine-input-node'

class QueueWorker
  constructor: ({@client,@timeout}) ->

  run: (callback) =>
    @client.brpop 'request:queue', @timeout, (error,result) =>
      return callback error if error?
      return callback() unless result?

      [queueName, requestStr] = result

      request = JSON.parse requestStr
      debug 'brpop', JSON.stringify request.metadata

      engineInput = new EngineInputNode
      inputStream = engineInput.message request

      inputStream.on 'data', =>

      inputStream.on 'end', =>
        debug "the worker noticed we ended"
        callback()
      inputStream.on 'error', =>
        debug "the worker thought we had an error"
        callback()

module.exports = QueueWorker
