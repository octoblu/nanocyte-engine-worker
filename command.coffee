_           = require 'lodash'
commander   = require 'commander'
async       = require 'async'
redis       = require 'redis'
RedisNS     = require '@octoblu/redis-ns'
debug       = require('debug')('nanocyte-engine-worker:command')
packageJSON = require './package.json'
QueueWorker = require './src/queue-worker'

debugLeak   = require('debug')('nanocyte-engine-worker:memwatch')
memwatch    = require 'memwatch-next'

memwatch.on 'stats', (stats) =>
  debugLeak 'stats:', JSON.stringify(stats, null, 2)

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
      .parse process.argv

    {@namespace,@singleRun,@timeout,@engineTimeout} = commander

    if process.env.NANOCYTE_ENGINE_WORKER_NAMESPACE?
      @namespace = process.env.NANOCYTE_ENGINE_WORKER_NAMESPACE

    if process.env.NANOCYTE_ENGINE_WORKER_SINGLE_RUN?
      @singleRun = process.env.NANOCYTE_ENGINE_WORKER_SINGLE_RUN == 'true'

    if process.env.NANOCYTE_ENGINE_WORKER_TIMEOUT?
      @timeout = parseInt process.env.NANOCYTE_ENGINE_WORKER_TIMEOUT

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
      client:        client
      timeout:       @timeout
      engineTimeout: @engineTimeout

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
