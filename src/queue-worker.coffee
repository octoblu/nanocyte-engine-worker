debug            = require('debug')('nanocyte-engine-worker:queue-worker')
Benchmark        = require 'simple-benchmark'
FlowSynchronizer = require 'nanocyte-configuration-synchronizer'

class QueueWorker
  constructor: (options) ->
    {@client,@timeout,@engineTimeout,@requestQueueName,@memoryLimit,@jobLogger,@dispatchLogger,@Engine} = options
    {cache, datastore} = options
    throw new Error 'cache is required' unless cache?
    throw new Error 'datastore is required' unless datastore?

    @requestQueueName ?=  'request:queue'
    @dispatchBenchmark  = new Benchmark label: 'QueueWorker'
    @flowSynchronizer   = new FlowSynchronizer {cache, datastore}

  run: (callback) =>
    process.nextTick =>
      if @memoryLimit?
        rss = process.memoryUsage().rss
        if rss > @memoryLimit * 1024 * 1024
          console.error "exiting with rss beyond limit at: #{rss}"
          process.exit 1

      @client.brpop @requestQueueName, @timeout, (error,result) =>
        return callback error if error?
        return callback() unless result?

        [queueName, requestStr] = result
        request = JSON.parse requestStr

        @dispatchLogger.log {request, elapsedTime: @dispatchBenchmark.elapsed()}, =>
          benchmark = new Benchmark label: 'engine-worker'

          @precacheJob request, (error) =>
            return callback error if error?
            @processJob request, (error) =>
              code = 200
              code = 500 if error?
              request = metadata: {toUuid: request.metadata.flowId}
              response = metadata: {code}

              @jobLogger.log {error,request,response,elapsedTime:benchmark.elapsed()}, (jobLoggerError) =>
                return callback jobLoggerError if jobLoggerError?
                callback error

  precacheJob: (request, callback) =>
    {flowId, instanceId} = request.metadata
    @flowSynchronizer.synchronizeByFlowIdAndInstanceId flowId, instanceId, callback

  processJob: (request, callback) =>
    debug 'brpop', request.metadata
    @flowId = request.metadata.flowId # used to output flowId in case of timeout

    benchmark = new Benchmark label: 'queue-worker'

    engine = new @Engine timeoutSeconds: @engineTimeout

    engine.run request, (error) =>
      debug "the worker thought we had an error", benchmark.toString() if error?
      debug "the worker noticed we ended", benchmark.toString()
      error.flowId = request.metadata?.flowId if error?

      callback error

module.exports = QueueWorker
