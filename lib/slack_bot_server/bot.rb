require 'slack'

class SlackBotServer::Bot
  attr_reader :key

  class InvalidToken < RuntimeError; end

  def initialize(token:, key: nil)
    @token = token
    @key = key || @token
    @api = ::Slack::Client.new(token: @token)
    @im_channel_ids = []

    raise InvalidToken unless auth_test['ok']
  end

  def say(options)
    @api.chat_postMessage(default_message_options.merge(options))
  end

  def reply(options)
    channel = @last_received_data['channel']
    @api.chat_postMessage(default_message_options.merge(options.merge(channel: channel)))
  end

  def say_to(user_id, options)
    result = @api.im_open(user: user_id)
    channel_id = result['channel']['id']
    say(options.merge(channel: channel_id))
  end

  def call(method, args)
    args.symbolize_keys!
    @api.send(method, args)
  end

  def start
    @ws = Faye::WebSocket::Client.new(websocket_url, nil, ping: 60)

    @ws.on :open do |event|
      log "connected to '#{team}'"
      load_im_channels
    end

    @ws.on :message do |event|
      begin
        debug event
        handle_message(event)
      rescue => e
        log error: e
      end
    end

    @ws.on :close do |event|
      log "disconnected"
    end
  end

  def stop
    log "closing connection"
    @ws.close
    log "closed"
  end

  class << self
    def username(name)
      default_message_options[:username] = name
    end

    def icon_url(url)
      default_message_options[:icon_url] = url
    end

    def default_message_options
      @default_message_options ||= {channel: '#general'}
    end

    def callbacks_for(type)
      callbacks = @callbacks[type.to_sym] || []
      if superclass.respond_to?(:callbacks_for)
        callbacks += superclass.callbacks_for(type)
      end
      callbacks
    end

    def on(type, &block)
      @callbacks ||= {}
      @callbacks[type.to_sym] ||= []
      @callbacks[type.to_sym] << block
    end

    def on_mention(&block)
      on(:message) do |data|
        if !bot_message?(data) &&
           (data['text'] =~ /\A#{user}[\s\:](.*)/ ||
            data['text'] =~ /\A<@#{user_id}>[\s\:](.*)/)
          message = $1.strip
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

  on :im_created do |data|
    channel_id = data['channel']['id']
    log "Adding new IM channel: #{channel_id}"
    @im_channel_ids << channel_id
  end

  def to_s
    "<#{self.class.name} key:#{key}>"
  end

  private

  def handle_message(event)
    data = MultiJson.load(event.data)
    if data["type"]
      relevant_callbacks = self.class.callbacks_for(data["type"])
      if relevant_callbacks && relevant_callbacks.any?
        relevant_callbacks.each do |c|
          instance_exec(data, &c)
        end
      end
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

  def user
    auth_test['user']
  end

  def user_id
    auth_test['user_id']
  end

  def team
    auth_test['team']
  end

  def auth_test
    @auth_test ||= @api.auth_test
  end

  def load_im_channels
    log "Loading IM channels"
    result = @api.im_list
    @im_channel_ids = result['ims'].map { |d| d['id'] }
    log im_channels: @im_channel_ids
  end

  def is_im_channel?(id)
    @im_channel_ids.include?(id)
  end

  def bot_message?(data)
    data['subtype'] == 'bot_message'
  end

  def websocket_url
    @api.post('rtm.start')['url']
  end

  def default_message_options
    self.class.default_message_options
  end
end
