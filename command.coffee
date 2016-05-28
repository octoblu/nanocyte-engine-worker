_           = require 'lodash'
commander   = require 'commander'
async       = require 'async'
JobLogger   = require 'job-logger'
redis       = require 'ioredis'
RedisNS     = require '@octoblu/redis-ns'
debug       = require('debug')('nanocyte-engine-worker:command')
packageJSON = require './package.json'
QueueWorker = require './src/queue-worker'
Engine      = require '@octoblu/nanocyte-engine-simple'

new Engine() # abosrb initial startup costs before brpop

class Command
  parseInt: (str) =>
    parseInt str

  parseOptions: =>
    commander
      .version packageJSON.version
      .option '-n, --namespace <nanocyte-engine>', 'job handler queue namespace.', 'nanocyte-engine'
      .option '-s, --single-run', 'perform only one job.'
      .option '-t, --timeout <45>', 'seconds to wait for a next job.', @parseInt, 45
      .option '--engine-timeout <90>', 'seconds to allow engine execution.', @parseInt, 90
      .option '--request-queue-name <request:queue>'
      .option '--memory-limit <unlimited>', 'in megabytes'
      .parse process.argv

    {@namespace,@singleRun,@timeout,@engineTimeout,@requestQueueName,@memoryLimit} = commander

    if process.env.NANOCYTE_ENGINE_WORKER_NAMESPACE?
      @namespace = process.env.NANOCYTE_ENGINE_WORKER_NAMESPACE

    if process.env.NANOCYTE_ENGINE_WORKER_SINGLE_RUN?
      @singleRun = process.env.NANOCYTE_ENGINE_WORKER_SINGLE_RUN == 'true'

    if process.env.NANOCYTE_ENGINE_WORKER_TIMEOUT?
      @timeout = parseInt process.env.NANOCYTE_ENGINE_WORKER_TIMEOUT

    if process.env.NANOCYTE_ENGINE_REQUEST_QUEUE_NAME?
      @requestQueueName = process.env.NANOCYTE_ENGINE_REQUEST_QUEUE_NAME

    if process.env.NANOCYTE_ENGINE_REQUEST_MEMORY_LIMIT?
      @memoryLimit = process.env.NANOCYTE_ENGINE_REQUEST_MEMORY_LIMIT

    throw new Error('env: JOB_LOG_REDIS_URI is required') unless process.env.JOB_LOG_REDIS_URI?
    @jobLogRedisUri = process.env.JOB_LOG_REDIS_URI
    throw new Error('env: JOB_LOG_QUEUE is required') unless process.env.JOB_LOG_QUEUE?
    @jobLogQueue = process.env.JOB_LOG_QUEUE
    throw new Error('env: JOB_LOG_SAMPLE_RATE is required') unless process.env.JOB_LOG_SAMPLE_RATE?
    @jobLogSampleRate = parseFloat process.env.JOB_LOG_SAMPLE_RATE

    if @memoryLimit?
      @memoryLimit = parseInt @memoryLimit

    @redisPort = process.env.REDIS_PORT
    @redisHost = process.env.REDIS_HOST

  run: =>
    @parseOptions()
    client = new RedisNS @namespace, redis.createClient(@redisPort, @redisHost, dropBufferSupport: true)
    jobLogClient = redis.createClient @jobLogRedisUri, dropBufferSupport: true
    jobLogger = new JobLogger
      client: jobLogClient
      indexPrefix: 'metric:nanocyte-engine-simple'
      type: 'metric:nanocyte-engine-simple:job'
      jobLogQueue: @jobLogQueue
      sampleRate: @jobLogSampleRate

    dispatchLogger = new JobLogger
      client: jobLogClient
      indexPrefix: 'metric:nanocyte-engine-simple'
      type: 'metric:nanocyte-engine-simple:dispatch'
      jobLogQueue: @jobLogQueue
      sampleRate: @jobLogSampleRate

    process.on 'SIGTERM', => @terminate = true
    return @queueWorkerRun client, jobLogger, dispatchLogger, @die if @singleRun
    async.until @terminated, async.apply(@queueWorkerRun, client, jobLogger, dispatchLogger), @die

  terminated: => @terminate

  queueWorkerRun: (client, jobLogger, dispatchLogger, callback) =>
    queueWorker = new QueueWorker {
      client
      jobLogger
      dispatchLogger
      @timeout
      @engineTimeout
      @requestQueueName
      @memoryLimit
      Engine
    }
    queueWorker.run (error) =>
      if error?
        console.log "Error flowId: #{error.flowId}"
        console.error error.stack
      process.nextTick callback

  die: (error) =>
    return process.exit(0) unless error?
    console.log "Error flowId: #{error.flowId}" if error.flowId?
    console.error error.stack
    process.exit 1

commandWork = new Command()
commandWork.run()
