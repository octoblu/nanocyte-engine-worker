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
      .option '-t, --timeout <15>', 'seconds to wait for a next job.', @parseInt, 15
      .parse process.argv

    {@namespace,@singleRun,@timeout} = commander

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
      client:    client
      timeout:   @timeout

    timeout = setTimeout =>
      @die new Error('Timeout exceeded, exiting')
    , (@timeout * 1000 * 2)

    queueWorker.run (error) =>
      console.error error.stack if error?
      clearTimeout timeout
      callback()

  die: (error) =>
    return process.exit(0) unless error?
    console.error error.stack
    process.exit 1

commandWork = new Command()
commandWork.run()
