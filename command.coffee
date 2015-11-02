commander    = require 'commander'
async        = require 'async'
redis        = require 'redis'
RedisNS      = require '@octoblu/redis-ns'
debug        = require('debug')('meshblu-core-dispatcher:command')
packageJSON  = require './package.json'
QueueWorker      = require './src/queue-worker'

class Command
  parseList: (val) =>
    val.split ','

  parseOptions: =>
    commander
      .version packageJSON.version
      .option '-n, --namespace <nanocyte-engine>', 'job handler queue namespace.', 'nanocyte-engine'
      .option '-s, --single-run', 'perform only one job.'
      .option '-t, --timeout <n>', 'seconds to wait for a next job.', parseInt, 30
      .parse process.argv

    {@namespace,@singleRun,@timeout} = commander
    @client = new RedisNS @namespace, redis.createClient(process.env.REDIS_URI)

    @redisUri   = process.env.REDIS_URI
    @pepper     = process.env.TOKEN

  run: =>
    @parseOptions()

    queueWorker = new QueueWorker
      client:    @client
      timeout:   @timeout

    if @singleRun
      queueWorker.run(@panic)
      return

    async.forever queueWorker.run, @panic

  panic: (error) =>
    console.error error.stack
    process.exit 1

commandWork = new Command()
commandWork.run()
