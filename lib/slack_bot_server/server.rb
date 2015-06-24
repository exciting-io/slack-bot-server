require 'slack_bot_server/bot'
require 'slack_bot_server/simple_bot'
require 'slack_bot_server/redis_queue'

class SlackBotServer::Server
  attr_reader :queue

  def initialize(queue: SlackBotServer::LocalQueue.new)
    @queue = queue
    @bots = {}
    @new_token_proc = -> (token) { SlackBotServer::SimpleBot.new(token: token) }
    @running = false
  end

  def on_new_token(&block)
    @new_token_proc = block
  end

  def start
    EM.run do
      @running = true
      @bots.each { |key, bot| bot.start }
      add_timers
    end
  end

  def add_timers
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

  def add_bot(bot)
    log "adding bot #{bot}"
    @bots[bot.key.to_sym] = bot
    bot.start if @running
  end

  def add_token(token)
    bot = @new_token_proc.call(token)
    add_bot(bot) if bot
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
    case type.to_sym
    when :add_token
      token = args.first
      log "got new token: '#{token}'"
      add_token(token)
    when :remove_bot
      key = args.first
      remove_bot(key)
    when :call
      key, method, method_args = args
      bot = bot(key)
      bot.call(method, method_args)
    else
      log unknown_command: instruction
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
end
