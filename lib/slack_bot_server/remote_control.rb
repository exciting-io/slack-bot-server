# Send commands to a running SlackBotServer::Server instance
#
# This should be initialized with a queue that is shared with the
# targetted server (e.g. the same local queue instance, or a
# redis queue instance that points at the same redis server).
class SlackBotServer::RemoteControl
  # Create a new instance of a remote control
  # @param queue [Object] any Object conforming to the queue API
  #   (i.e. with #push and #pop methods)
  def initialize(queue:)
    @queue = queue
  end

  # Sends an +add_bot+ command to the {SlackBotServer::Server server}.
  # See {SlackBotServer::Server#add_bot} for arguments.
  def add_bot(*args)
    @queue.push([:add_bot, *args])
  end

  # Sends a +remove_bot+ command to the server.
  # @param key [String] the key of the bot to remove.
  def remove_bot(key)
    @queue.push([:remove_bot, key])
  end

  # Sends an +broadcast+ command to the {SlackBotServer::Server server}.
  # @param key [String] the key of the bot which should send the message
  # @param message_data [Hash] passed directly to
  #    {SlackBotServer::Bot#broadcast}; see there for argument details.
  def broadcast(key, message_data)
    @queue.push([:broadcast, key, message_data])
  end

  # Sends an +say+ command to the {SlackBotServer::Server server}.
  # @param key [String] the key of the bot which should send the message.
  # @param message_data [Hash] passed directly to
  #    {SlackBotServer::Bot#say}; see there for argument details.
  def say(key, message_data)
    @queue.push([:say, key, message_data])
  end

  # Sends an +say_to+ command to the {SlackBotServer::Server server}.
  # @param key [String] the key of the bot which should send the message.
  # @param user_id [String] the Slack user ID of the person who should
  #    receive the message.
  # @param message_data [Hash] passed directly to
  #    {SlackBotServer::Bot#say_to}; see there for argument details.
  def say_to(key, user_id, message_data)
    @queue.push([:say_to, key, user_id, message_data])
  end

  # Sends a message to be called directly on the slack web API. Generally
  # for debugging only.
  # @param key [String] the key of the bot which should send the message.
  # @param method [String, Symbol] the name of the method to call
  # @param args [Array] the arguments for the method to call
  def call(key, method, args)
    @queue.push([:call, [key, method, args]])
  end
end
