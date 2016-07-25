uuid      = require 'uuid'
mongojs   = require 'mongojs'
redis     = require 'fakeredis'
JobLogger = require 'job-logger'
RedisNS   = require '@octoblu/redis-ns'
Engine    = require '@octoblu/nanocyte-engine-simple'

new Engine()

describe 'QueueWorker', ->
  it 'should not blow up', ->
    @redisKey = uuid.v1()
    cache = redis.createClient @redisKey, dropBufferSupport: true
    mongo = mongojs 'the-engine-worker-test-db', ['instances']
    datastore = mongo.instances

    client = new RedisNS 'the-redis-worker-test-client', redis.createClient @redisKey, dropBufferSupport: true
    jobLogClient = redis.createClient uuid.v1(), dropBufferSupport: true
    jobLogger = new JobLogger
      client: jobLogClient
      indexPrefix: 'metric:nanocyte-engine-simple'
      type: 'metric:nanocyte-engine-simple:job'
      jobLogQueue: 1
      sampleRate: 1

    dispatchLogger = new JobLogger
      client: jobLogClient
      indexPrefix: 'test:metric:nanocyte-engine-simple'
      type: 'test:metric:nanocyte-engine-simple:dispatch'
      jobLogQueue: 1
      sampleRate: 1

    expect( =>
      @sut = new QueueWorker {
        cache
        datastore
        client
        jobLogger
        dispatchLogger
        timeout: 1
        engineTimeout: 1
        requestQueueName: 'test-engine-worker-queue'
        memoryLimit: 100,
        Engine
      }
    ).to.not.throw
