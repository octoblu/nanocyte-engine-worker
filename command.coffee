commander   = require 'commander'
async       = require 'async'
JobLogger   = require 'job-logger'
redis       = require 'ioredis'
mongojs     = require 'mongojs'
RedisNS     = require '@octoblu/redis-ns'
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

    throw new Error('env: MONGODB_URI is required') unless process.env.MONGODB_URI
    @mongoUri = process.env.MONGODB_URI

    if @memoryLimit?
      @memoryLimit = parseInt @memoryLimit

    @redisUri = process.env.REDIS_URI
    throw new Error('env: REDIS_URI is required') unless process.env.REDIS_URI

  run: =>
    @parseOptions()

    cache = redis.createClient @redisUri, dropBufferSupport: true
    mongo = mongojs @mongoUri, ['instances']

    mongo.runCommand {ping: 1}, (error) =>
      return callback error if error?

      setInterval =>
        mongo.runCommand {ping: 1}, (error) =>
          @die error if error?
      , 10 * 1000

    datastore = mongo.instances

    client = new RedisNS @namespace, redis.createClient(@redisUri, dropBufferSupport: true)
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
    return @queueWorkerRun cache, datastore, client, jobLogger, dispatchLogger, @die if @singleRun
    async.until @terminated, async.apply(@queueWorkerRun, cache, datastore, client, jobLogger, dispatchLogger), @die

  terminated: => @terminate

  queueWorkerRun: (cache, datastore, client, jobLogger, dispatchLogger, callback) =>
    queueWorker = new QueueWorker {
      cache
      datastore
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
