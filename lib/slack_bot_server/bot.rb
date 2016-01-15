require 'slack'
require 'slack-ruby-client'

class SlackBotServer::Bot
  SLACKBOT_USER_ID = 'USLACKBOT'

  attr_reader :key, :token

  class InvalidToken < RuntimeError; end

  def initialize(token:, key: nil)
    @token = token
    @key = key || @token
    @client = ::Slack::RealTime::Client.new(token: @token)
    @im_channel_ids = []
    @channel_ids = []
    @connected = false
    @running = false

    raise InvalidToken unless @client.web_client.auth_test['ok']
  end

  def user
    @client.self['name']
  end

  def user_id
    @client.self['id']
  end

  def team
    @client.team['name']
  end

  def team_id
    @client.team['id']
  end

  def say(options)
    message = symbolize_keys(default_message_options.merge(options))

    if rtm_incompatible_message?(message)
      debug "Sending via Web API", message
      @client.web_client.chat_postMessage(message)
    else
      debug "Sending via RTM API", message
      @client.message(message)
    end
  end

  def broadcast(options)
    @channel_ids.each do |channel|
      say(options.merge(channel: channel))
    end
  end

  def reply(options)
    channel = @last_received_data['channel']
    say(options.merge(channel: channel))
  end

  def say_to(user_id, options)
    result = @client.web_client.im_open(user: user_id)
    channel = result['channel']['id']
    say(options.merge(channel: channel))
  end

  def typing(options={})
    last_received_channel = @last_received_data ? @last_received_data['channel'] : nil
    default_options = {channel: last_received_channel}
    @client.typing(default_options.merge(options))
  end

  def call(method, args)
    args.symbolize_keys!
    @client.web_client.send(method, args)
  end

  def start
    @running = true

    @client.on :open do |event|
      @connected = true
      log "connected to '#{team}'"
      run_callbacks(:start)
    end

    @client.on :message do |data|
      begin
        debug message: data
        handle_message(data)
      rescue => e
        log error: e
        log backtrace: e.backtrace
      end
    end

    @client.on :im_created do |data|
      channel_id = data['channel']['id']
      log "Adding new IM channel: #{channel_id}"
      @im_channel_ids << channel_id
    end

    @client.on :channel_joined do |data|
      channel_id = data['channel']['id']
      log "Adding new channel: #{channel_id}"
      @channel_ids << channel_id
    end

    @client.on :channel_left do |data|
      channel_id = data['channel']
      log "Removing channel: #{channel_id}"
      @channel_ids.delete(channel_id)
    end

    @client.on :close do |event|
      log "disconnected"
      @connected = false
      if @running
        start
      end
    end

    @client.start_async
  end

  def stop
    log "closing connection"
    @running = false
    @client.stop!
    log "closed"
  end

  def running?
    @running
  end

  def connected?
    @connected
  end

  class << self
    attr_reader :mention_keywords

    def username(name)
      default_message_options[:username] = name
    end

    def icon_url(url)
      default_message_options[:icon_url] = url
    end

    def mention_as(*keywords)
      @mention_keywords = keywords
    end

    def default_message_options
      @default_message_options ||= {type: 'message'}
    end

    def callbacks
      @callbacks ||= {}
    end

    def callbacks_for(type)
      if superclass.respond_to?(:callbacks_for)
        matching_callbacks = superclass.callbacks_for(type)
      else
        matching_callbacks = []
      end
      matching_callbacks += callbacks[type.to_sym] if callbacks[type.to_sym]
      matching_callbacks
    end

    def on(type, &block)
      callbacks[type.to_sym] ||= []
      callbacks[type.to_sym] << block
    end

    def on_mention(&block)
      on(:message) do |data|
        debug on_message: data, bot_message: bot_message?(data)
        if !bot_message?(data) &&
           (data['text'] =~ /\A(#{mention_keywords.join('|')})[\s\:](.*)/i ||
            data['text'] =~ /\A(<@#{user_id}>)[\s\:](.*)/)
          message = $2.strip
          @last_received_data = data.merge('message' => message)
          instance_exec(@last_received_data, &block)
        end
      end
    end

    def on_im(&block)
      on(:message) do |data|
        debug on_im: data, bot_message: bot_message?(data), is_im_channel: is_im_channel?(data['channel'])
        if is_im_channel?(data['channel']) && !bot_message?(data)
          @last_received_data = data.merge('message' => data['text'])
          instance_exec(@last_received_data, &block)
        end
      end
    end
  end

  on :start do
    load_channels
  end

  def to_s
    "<#{self.class.name} key:#{key}>"
  end

  private

  def handle_message(data)
    run_callbacks(data['type'], data)
  end

  def run_callbacks(type, data=nil)
    relevant_callbacks = self.class.callbacks_for(type)
    relevant_callbacks.each do |c|
      response = instance_exec(data, &c)
      break if response == false
    end
  end

  def log(*args)
    SlackBotServer.logger.info(log_string(*args))
  end

  def debug(*args)
    SlackBotServer.logger.debug(log_string(*args))
  end

  def log_string(*args)
    text = if args.length == 1 && args.first.is_a?(String)
      args.first
    else
      args.map { |a| a.is_a?(String) ? a : a.inspect }.join(", ")
    end
    "[BOT/#{user}] #{text}"
  end

  def load_channels
    log "Loading channels"
    @im_channel_ids = @client.ims.map { |d| d['id'] }
    log im_channels: @im_channel_ids
    @channel_ids = @client.channels.select { |d| d['is_member'] == true }.map { |d| d['id'] }
    log channels: @channel_ids
  end

  def is_im_channel?(id)
    @im_channel_ids.include?(id)
  end

  def bot_message?(data)
    data['subtype'] == 'bot_message' ||
    data['user'] == SLACKBOT_USER_ID ||
    data['user'] == user_id ||
    change_to_previous_bot_message?(data)
  end

  def change_to_previous_bot_message?(data)
    data['subtype'] == 'message_changed' &&
    data['previous_message']['user'] == user_id
  end

  def rtm_incompatible_message?(data)
    data[:attachments].nil? ||
    data[:username].nil? ||
    data[:icon_url].nil? ||
    data[:icon_emoji].nil? ||
    data[:channel].match(/^#/).nil?
  end

  def default_message_options
    self.class.default_message_options
  end

  def mention_keywords
    self.class.mention_keywords || [user]
  end

  def symbolize_keys(hash)
    hash.keys.each do |key|
      hash[key.to_sym] = hash.delete(key)
    end
    hash
  end
end
