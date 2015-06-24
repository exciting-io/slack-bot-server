require 'multi_json'

class SlackBotServer::RedisQueue
  def initialize(redis)
    @key = 'slack_bot_server:queue'
    @redis = redis
  end

  def push(value)
    @redis.rpush @key, MultiJson.dump(value)
  end

  def pop
    json_value = @redis.lpop @key
    if json_value
      MultiJson.load(json_value)
    else
      nil
    end
  end
end

