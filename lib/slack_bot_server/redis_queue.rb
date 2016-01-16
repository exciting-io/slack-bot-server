require 'multi_json'

# An implementation of the quue interface that uses
# Redis as a data conduit.
class SlackBotServer::RedisQueue
  # Creates a new queue
  # @param redis [Redis] an instance of the ruby +Redis+ client. If
  #    nil, one will be created using the default hostname and port
  # @param key [String] the key to store the queue against
  def initialize(redis: nil, key: 'slack_bot_server:queue')
    @key = key
    @redis = if redis
      redis
    else
      require 'redis'
      Redis.new
    end
  end

  # Push a value onto the back of the queue.
  # @param value [Object] this will be turned into JSON when stored
  def push(value)
    @redis.rpush @key, MultiJson.dump(value)
  end

  # Pop a value from the front of the queue
  # @return [Object] the object on the queue, reconstituted from its
  #    JSON string
  def pop
    json_value = @redis.lpop @key
    if json_value
      MultiJson.load(json_value, symbolize_keys: true)
    else
      nil
    end
  end
end
