_           = require 'lodash'
commander   = require 'commander'
async       = require 'async'
redis       = require 'redis'
RedisNS     = require '@octoblu/redis-ns'
debug       = require('debug')('nanocyte-engine-worker:command')
packageJSON = require './package.json'
QueueWorker = require './src/queue-worker'

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

    if @memoryLimit?
      @memoryLimit = parseInt @memoryLimit

    @redisPort = process.env.REDIS_PORT
    @redisHost = process.env.REDIS_HOST

  run: =>
    @parseOptions()
    client = new RedisNS @namespace, redis.createClient(@redisPort, @redisHost)

    process.on 'SIGTERM', => @terminate = true
    return @queueWorkerRun client, @die if @singleRun
    async.until @terminated, async.apply(@queueWorkerRun, client), @die

  terminated: => @terminate

  queueWorkerRun: (client, callback) =>
    queueWorker = new QueueWorker
      client:           client
      timeout:          @timeout
      engineTimeout:    @engineTimeout
      requestQueueName: @requestQueueName
      memoryLimit:      @memoryLimit

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
