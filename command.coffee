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
      .option '-c, --concurrency <1>', 'number of workers to run at a time', @parseInt, 1
      .option '-n, --namespace <nanocyte-engine>', 'job handler queue namespace.', 'nanocyte-engine'
      .option '-s, --single-run', 'perform only one job.'
      .option '-t, --timeout <30>', 'seconds to wait for a next job.', @parseInt, 30
      .parse process.argv

    {@concurrency,@namespace,@singleRun,@timeout} = commander

    if process.env.NANOCYTE_ENGINE_WORKER_CONCURRENCY?
      @concurrency = parseInt process.env.NANOCYTE_ENGINE_WORKER_CONCURRENCY

    if process.env.NANOCYTE_ENGINE_WORKER_NAMESPACE?
      @namespace = process.env.NANOCYTE_ENGINE_WORKER_NAMESPACE

    if process.env.NANOCYTE_ENGINE_WORKER_SINGLE_RUN?
      @singleRun = process.env.NANOCYTE_ENGINE_WORKER_SINGLE_RUN == 'true'

    if process.env.NANOCYTE_ENGINE_WORKER_TIMEOUT?
      @timeout = parseInt process.env.NANOCYTE_ENGINE_WORKER_TIMEOUT

    @client = new RedisNS @namespace, redis.createClient(process.env.REDIS_PORT, process.env.REDIS_HOST)

  run: =>
    @parseOptions()
    async.times @concurrency, @work, @die

  work: (i, callback) =>
    return @queueWorkerRun callback if @singleRun
    async.forever @queueWorkerRun, callback

  queueWorkerRun: (callback) =>
    queueWorker = new QueueWorker
      client:    @client
      timeout:   @timeout

    queueWorker.run (error) =>
      console.error error.stack if error?
      callback()

  die: (error) =>
    return process.exit(0) unless error?
    console.error error.stack
    process.exit 1

commandWork = new Command()
commandWork.run()
