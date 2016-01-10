# Send commands to a running SlackBotServer::Server instance
#
# This should be initialized with a queue that is shared with the
# targetted server (e.g. the same local queue instance, or a
# redis queue instance that points at the same redis server).

class SlackBotServer::RemoteControl
  def initialize(queue:)
    @queue = queue
  end

  def add_bot(*args)
    @queue.push([:add_bot, *args])
  end

  def remove_bot(key)
    @queue.push([:remove_bot, key])
  end

  def broadcast(key, message_data)
    @queue.push([:broadcast, key, message_data])
  end

  def say(key, message_data)
    @queue.push([:say, key, message_data])
  end

  def say_to(key, user_id, message_data)
    @queue.push([:say_to, key, user_id, message_data])
  end

  def call(key, method, args)
    @queue.push([:call, [key, method, args]])
  end
end
