require 'slack'
require 'slack/client'
require 'faye/websocket'

class SlackBotServer::Bot
  SLACKBOT_USER_ID = 'USLACKBOT'

  attr_reader :key

  class InvalidToken < RuntimeError; end

  def initialize(token:, key: nil)
    @token = token
    @key = key || @token
    @api = ::Slack::Client.new(token: @token)
    @im_channel_ids = []
    @channel_ids = []
    @connected = false
    @running = false

    raise InvalidToken unless rtm_start_data['ok']
  end

  def user
    rtm_start_data['self']['name']
  end

  def user_id
    rtm_start_data['self']['id']
  end

  def team
    rtm_start_data['team']['name']
  end

  def team_id
    rtm_start_data['team']['id']
  end

  def say(options)
    @api.chat_postMessage(default_message_options.merge(options))
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
    result = @api.im_open(user: user_id)
    channel = result['channel']['id']
    say(options.merge(channel: channel))
  end

  def call(method, args)
    args.symbolize_keys!
    @api.send(method, args)
  end

  def start
    @running = true
    @ws = Faye::WebSocket::Client.new(websocket_url, nil, ping: 60)

    @ws.on :open do |event|
      @connected = true
      log "connected to '#{team}'"
      run_callbacks(:start)
    end

    @ws.on :message do |event|
      begin
        debug event.data
        handle_message(event)
      rescue => e
        log error: e
        log backtrace: e.backtrace
      end
    end

    @ws.on :close do |event|
      log "disconnected"
      @connected = false
      if @running
        start
      end
    end
  end

  def stop
    log "closing connection"
    @running = false
    @ws.close
    log "closed"
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
      @default_message_options ||= {}
    end

    def callbacks
      @callbacks ||= {}
    end

    def callbacks_for(type)
      matching_callbacks = callbacks[type.to_sym] || []
      if superclass.respond_to?(:callbacks_for)
        matching_callbacks += superclass.callbacks_for(type)
      end
      matching_callbacks.reverse
    end

    def on(type, &block)
      callbacks[type.to_sym] ||= []
      callbacks[type.to_sym] << block
    end

    def on_mention(&block)
      on(:message) do |data|
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

  on :im_created do |data|
    channel_id = data['channel']['id']
    log "Adding new IM channel: #{channel_id}"
    @im_channel_ids << channel_id
  end

  on :channel_joined do |data|
    channel_id = data['channel']['id']
    log "Adding new channel: #{channel_id}"
    @channel_ids << channel_id
  end

  on :channel_left do |data|
    channel_id = data['channel']
    log "Removing channel: #{channel_id}"
    @channel_ids.delete(channel_id)
  end

  def to_s
    "<#{self.class.name} key:#{key}>"
  end

  private

  def handle_message(event)
    data = MultiJson.load(event.data)
    run_callbacks(data["type"], data) if data["type"]
  end

  def run_callbacks(type, data=nil)
    relevant_callbacks = self.class.callbacks_for(type)
    relevant_callbacks.each do |c|
      instance_exec(data, &c)
    end
  end

  def log(message)
    text = message.is_a?(String) ? message : message.inspect
    text = "[BOT/#{user}] #{text}"
    SlackBotServer.logger.info(message)
  end

  def debug(message)
    text = message.is_a?(String) ? message : message.inspect
    text = "[BOT/#{user}] #{text}"
    SlackBotServer.logger.debug(message)
  end

  def load_channels
    log "Loading channels"
    @im_channel_ids = rtm_start_data['ims'].map { |d| d['id'] }
    log im_channels: @im_channel_ids
    @channel_ids = rtm_start_data['channels'].select { |d| d['is_member'] == true }.map { |d| d['id'] }
    log channels: @channel_ids
  end

  def websocket_url
    rtm_start_data['url']
  end

  def rtm_start_data
    @rtm_start_data ||= @api.post('rtm.start')
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

  def websocket_url
    @api.post('rtm.start')['url']
  end

  def default_message_options
    self.class.default_message_options
  end

  def mention_keywords
    self.class.mention_keywords || [user]
  end
end
