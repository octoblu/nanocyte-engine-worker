Benchmark        = require 'simple-benchmark'
FlowSynchronizer = require 'nanocyte-configuration-synchronizer'
debug            = require('debug')('nanocyte-engine-worker:queue-worker')

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
          @possiblyDeleteCache request, (error) =>
            return callback error if error?

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

  precacheJob: ({metadata}, callback) =>
    {flowId, instanceId} = metadata
    @flowSynchronizer.synchronizeByFlowIdAndInstanceId flowId, instanceId, callback

  possiblyDeleteCache: ({message, metadata}, callback) =>
    return callback() unless @isDeleteCacheMessage {metadata, message}

    {flowId, instanceId} = metadata
    @flowSynchronizer.clearByFlowIdAndInstanceId flowId, instanceId, callback


  isDeleteCacheMessage: ({metadata, message}) =>
    return true if message?.payload?.from == 'engine-start'
    return true if message?.payload?.from == 'engine-stop'

    return true if metadata?.to?.nodeId == 'engine-start'
    return true if metadata?.to?.nodeId == 'engine-stop'

    return false

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
