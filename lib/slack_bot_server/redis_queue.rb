require 'multi_json'

class SlackBotServer::RedisQueue
  def initialize(redis=nil)
    @key = 'slack_bot_server:queue'
    @redis = if redis
      redis
    else
      require 'redis'
      Redis.new
    end
  end

  def push(value)
    @redis.rpush @key, MultiJson.dump(value)
  end

  def pop
    json_value = @redis.lpop @key
    if json_value
      MultiJson.load(json_value, symbolize_keys: true)
    else
      nil
    end
  end
end

