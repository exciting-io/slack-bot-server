require 'slack_bot_server/bot'
require 'slack_bot_server/simple_bot'
require 'slack_bot_server/redis_queue'
require 'eventmachine'

class SlackBotServer::Server
  attr_reader :queue

  def initialize(queue: SlackBotServer::LocalQueue.new)
    @queue = queue
    @bots = {}
    @add_proc = -> (token) { SlackBotServer::SimpleBot.new(token: token) }
    @running = false
  end

  # Define the block which should be called when the `add_bot` method is
  # called, or the `add_bot` message is sent via a queue. This block
  # should return a bot (which responds to start), in which case it will
  # be added and started. If anything else is returned, it will be ignored.
  def on_add(&block)
    @add_proc = block
  end

  def start
    EM.run do
      @running = true
      @bots.each { |key, bot| bot.start }
      listen_for_instructions if queue
    end
  end

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

  def start_in_background
    Thread.start { start }
  end

  def bot(key)
    @bots[key.to_sym]
  end

  def add_bot(*args)
    bot = @add_proc.call(*args)
    if bot.respond_to?(:start)
      log "adding bot #{bot}"
      @bots[bot.key.to_sym] = bot
      bot.start if @running
    end
  rescue => e
    log_error(e)
  end

  def remove_bot(key)
    if (bot = bot(key))
      bot.stop
      @bots.delete(key.to_sym)
    end
  rescue => e
    log_error(e)
  end

  private

  def process_instruction(instruction)
    type, *args = instruction
    bot_key = args.shift
    if type == :add_bot
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

  def log(message)
    text = message.is_a?(String) ? message : message.inspect
    SlackBotServer.logger.info(text)
  end

  def log_error(e)
    SlackBotServer.logger.warn("Error in server: #{e} - #{e.message}")
    SlackBotServer.logger.warn(e.backtrace.join("\n"))
  end

  def with_bot(key)
    if bot = bot(key)
      yield bot
    else
      log("Unknown bot: #{key}")
    end
  end
end
