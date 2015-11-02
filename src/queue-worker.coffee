EngineInputNode = require '@octoblu/nanocyte-engine-simple/src/models/engine-input-node'

class QueueWorker
  constructor: ({@client,@timeout}) ->

  run: (callback) =>
    @client.brpop 'request:queue', @timeout, (error,result) =>
      return callback error if error?
      return callback() unless result?

      [queueName, requestStr] = result

      request = JSON.parse requestStr

      engineInput = new EngineInputNode
      inputStream = engineInput.message request

      inputStream.on 'end', callback
      inputStream.on 'error', callback

module.exports = QueueWorker
