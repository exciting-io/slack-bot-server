require 'slack_bot_server/bot'
require 'slack_bot_server/simple_bot'
require 'slack_bot_server/redis_queue'
require 'slack_bot_server/logging'
require 'eventmachine'

# Implements a server for running multiple Slack bots. Bots can be
# dynamically added and removed, and can be interacted with from
# external services (like your application).
#
# To use this, you should create a script to run along side your
# application. A simple example:
#
#     #!/usr/bin/env ruby
#
#     require 'slack_bot_server'
#     require 'slack_bot_server/redis_queue'
#     require 'slack_bot_server/simple_bot'
#
#     # Use a Redis-based queue to add/remove bots and to trigger
#     # bot messages to be sent
#     queue = SlackBotServer::RedisQueue.new
#
#     # Create a new server using that queue
#     server = SlackBotServer::Server.new(queue: queue)
#
#     # How your application-specific should be created when the server
#     # is told about a new slack api token to connect with
#     server.on_add do |token|
#       # Return a new bot instance to the server. `SimpleBot` is a provided
#       # example bot with some very simple behaviour.
#       SlackBotServer::SimpleBot.new(token: token)
#     end
#
#     # Start the server. This method blocks, and will not return until
#     # the server is killed.
#     server.start
#
# The key features are:
#
# * creating a queue as a conduit for commands from your app
# * creating an instance of {Server} with that queue
# * defining an #on_add block, which is run whenever you need to
#   start a new bot. This block contains the custom code relevant to
#   your particular service, most typically the instantiation of a bot
#   class that implements the logic you want
# * calling {Server#start}, to actually run the server and start
#   listening for commands from the queue and connecting bots to Slack
#   itself
#
class SlackBotServer::Server
  include SlackBotServer::Logging

  attr_reader :queue

  # Creates a new {Server}
  # @param queue [Object] anything that implements the queue protocol
  #   (e.g. #push and #pop)
  def initialize(queue: SlackBotServer::LocalQueue.new)
    @queue = queue
    @bots = {}
    @add_proc = -> (token) { SlackBotServer::SimpleBot.new(token: token) }
    @running = false
  end

  # Define the block which should be called when the #add_bot method is
  # called, or the +add_bot+ message is sent via a queue. This block
  # should return a bot (which responds to start), in which case it will
  # be added and started. If anything else is returned, it will be ignored.
  def on_add(&block)
    @add_proc = block
  end

  # Starts the server. This method will not return; call it at the
  # end of your server script. It will start all bots it knows about
  # (i.e. bots added via #add_bot before the server was started),
  # and then listen for new instructions.
  # @see Bot#start
  def start
    EM.run do
      @running = true
      @bots.each do |key, bot|
        begin
          bot.start
        rescue => e
          log_error(e)
        end
      end
      listen_for_instructions if queue
    end
  end

  # Starts the server in the background, via a Thread
  def start_in_background
    Thread.start { start }
  end

  # Find a bot added to this server. Returns nil if no bot was found
  # @param key [String] the key of the bot we're looking for
  # @return Bot
  def bot(key)
    @bots[key]
  end

  # Adds a bot to this server
  # Calls the block given to {#on_add} with the arguments given. The block
  # should yield a bot, typically a subclass of {Bot}.
  # @see #on_add
  def add_bot(*args)
    bot = @add_proc.call(*args)
    if bot.respond_to?(:start) && !bot(bot.key)
      log "adding bot #{bot}"
      @bots[bot.key] = bot
      bot.start if @running
    end
  rescue => e
    log_error(e)
  end

  # Stops and removes a bot from the server
  # @param key [String] the key of the bot to remove
  # @see SlackBotServer::Bot#stop
  def remove_bot(key)
    if (bot = bot(key))
      bot.stop
      @bots.delete(key)
    end
  rescue => e
    log_error(e)
  end

  private

  def listen_for_instructions
    EM.add_periodic_timer(1) do
      begin
        next_message = queue.pop
        process_instruction(next_message) if next_message
      rescue => e
        log_error(e)
      end
    end
  end

  def process_instruction(instruction)
    type, *args = instruction
    bot_key = args.shift
    if type.to_sym == :add_bot
      log "adding bot: #{bot_key} #{args.inspect}"
      add_bot(bot_key, *args)
    else
      with_bot(bot_key) do |bot|
        case type.to_sym
        when :remove_bot
          remove_bot(bot_key)
        when :broadcast
          log "[#{bot_key}] broadcast: #{args}"
          bot.broadcast(*args)
        when :say
          log "[#{bot_key}] say: #{args}"
          bot.say(*args)
        when :say_to
          user_id, message_data = args
          log "[#{bot_key}] say_to: (#{user_id}) #{message_data}"
          bot.say_to(user_id, message_data)
        when :call
          method, method_args = args
          bot.call(method, method_args)
        else
          log unknown_command: instruction
        end
      end
    end
  end

  # def log(message)
  #   text = message.is_a?(String) ? message : message.inspect
  #   SlackBotServer.logger.info(text)
  # end

  def with_bot(key)
    if bot = bot(key)
      yield bot
    else
      log("Unknown bot: #{key}")
    end
  end
end
