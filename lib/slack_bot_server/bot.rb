require 'slack_bot_server/logging'
require 'slack'
require 'slack-ruby-client'

# A superclass for integration bot implementations.
#
# A simple example:
#
#   class MyBot < SlackBotServer::Bot
#     # Set the friendly username displayed in Slack
#     username 'My Bot'
#     # Set the image to use as an avatar icon in Slack
#     icon_url 'http://my.server.example.com/assets/icon.png'
#
#     # Respond to mentions in the connected chat room (defaults to #general).
#     # As well as the normal data provided by Slack's API, we add the `message`,
#     # which is the `text` parameter with the username stripped out. For example,
#     # When a user sends 'simple_bot: how are you?', the `message` data contains
#     # only 'how are you'.
#     on_mention do |data|
#       if data['message'] == 'who are you'
#         reply text: "I am #{bot_user_name} (user id: #{bot_user_id}, connected to team #{team_name} with team id #{team_id}"
#       else
#         reply text: "You said '#{data['message']}', and I'm frankly fascinated."
#       end
#     end
#
#     # Respond to messages sent via IM communication directly with the bot.
#     on_im do
#       reply text: "Hmm, OK, let me get back to you about that."
#     end
#   end
#
class SlackBotServer::Bot
  include SlackBotServer::Logging
  extend SlackBotServer::Logging

  # The user ID of the special slack user +SlackBot+
  SLACKBOT_USER_ID = 'USLACKBOT'

  attr_reader :key, :token, :client

  # Raised if there was an error while trying to connect to Slack
  class ConnectionError < Slack::Web::Api::Error; end

  # Create a new bot.
  # This is normally called from within the block passed to
  # {SlackBotServer::Server#on_add}, which should return a new
  # bot instance.
  # @param token [String] the Slack bot token to use for authentication
  # @param key [String] a key used to target messages to this bot from
  #    your application when using {RemoteControl}. If not provided,
  #    this defaults to the token.
  def initialize(token:, key: nil)
    @token = token
    @key = key || @token
    @connected = false
    @running = false
  end

  # Returns the username (for @ replying) of the bot user we are connected as,
  # e.g. +'simple_bot'+
  def bot_user_name
    client.self.name
  end

  # Returns the ID of the bot user we are connected as, e.g. +'U123456'+
  def bot_user_id
    client.self.id
  end

  # Returns the name of the team we are connected to, e.g. +'My Team'+
  def team_name
    client.team.name
  end

  # Returns the ID of the team we are connected to, e.g. +'T234567'+
  def team_id
    client.team.id
  end

  # Send a message to Slack
  # @param options [Hash] a hash containing any of the following:
  #    channel:: the name ('#general'), or the ID of the channel to send to
  #    text:: the actual text of the message
  #    username:: the name the message should appear from; defaults to the
  #               value given to `username` in the Bot class definition
  #    icon_url:: the image url to use as the avatar for this message;
  #               defaults to the value given to `icon_url` in the Bot
  #               class definition
  def say(options)
    message = symbolize_keys(default_message_options.merge(options))

    if rtm_incompatible_message?(message)
      debug "Sending via Web API", message
      client.web_client.chat_postMessage(message)
    else
      debug "Sending via RTM API", message
      client.message(message)
    end
  end

  # Sends a message to every channel this bot is a member of
  # @param options [Hash] As {#say}, although the +:channel+ option is
  #   redundant
  def broadcast(options)
    client.channels.each do |id, _|
      say(options.merge(channel: id))
    end
  end

  # Sends a reply to the same channel as the last message that was
  # received by this bot.
  # @param options [Hash] As {#say}, although the +:channel+ option is
  #    redundant
  def reply(options)
    channel = @last_received_user_message.channel
    say(options.merge(channel: channel))
  end

  # Sends a message via IM to a user
  # @param user_id [String] the Slack user ID of the person to receive this message
  # @param options [Hash] As {#say}, although the +:channel+ option is
  #    redundant
  def say_to(user_id, options)
    result = client.web_client.im_open(user: user_id)
    channel = result.channel.id
    say(options.merge(channel: channel))
  end

  # Sends a typing notification
  # @param options [Hash] can contain +:channel+, which should be an ID; if no options
  #    are provided, the channel from the most recently recieved message is used
  def typing(options={})
    last_received_channel = @last_received_user_message ? @last_received_user_message.channel : nil
    default_options = {channel: last_received_channel}
    client.typing(default_options.merge(options))
  end

  # Call a method directly on the Slack web API (via Slack::Web::Client).
  # Useful for debugging only.
  def call(method, args)
    args.symbolize_keys!
    client.web_client.send(method, args)
  end

  # Starts the bot running.
  # You should not call this method; instead, the server will call it
  # when it is ready for the bot to connect
  # @see Server#start
  def start
    @client = ::Slack::RealTime::Client.new(token: @token)
    @running = true

    client.on :open do |event|
      @connected = true
      log "connected to '#{team_name}'"
      run_callbacks(:start)
    end

    client.on :message do |data|
      begin
        debug message: data
        @last_received_user_message = data if user_message?(data)
        handle_message(data)
      rescue => e
        log_error e
      end
    end

    client.on :close do |event|
      log "disconnected"
      @connected = false
      run_callbacks(:finish)
    end

    register_low_level_callbacks

    client.start_async
  rescue Slack::Web::Api::Error => e
    raise ConnectionError.new(e.message, e.response)
  end

  # Stops the bot from running. You should not call this method; instead
  # send the server a +remote_bot+ message
  # @see Server#remove_bot
  def stop
    log "closing connection"
    @running = false
    client.stop!
    log "closed"
  end

  # Returns +true+ if this bot is (or should be) running
  def running?
    @running
  end

  # Returns +true+ if this bot is currently connected to Slack
  def connected?
    @connected
  end

  class << self
    attr_reader :mention_keywords

    # Sets the username this bot should use
    #
    #   class MyBot < SlackBotServer::Bot
    #     username 'My Bot'
    #
    #     # etc
    #   end
    #
    # will result in the friendly name 'My Bot' appearing beside
    # the messages in your Slack rooms
    def username(name)
      default_message_options[:username] = name
    end

    # Sets the image to use as an avatar for this bot
    #
    #   class MyBot < SlackBotServer::Bot
    #     icon_url 'http://example.com/bot.png'
    #
    #     # etc
    #   end
    def icon_url(url)
      default_message_options[:icon_url] = url
    end

    # Sets the keywords in messages that will trigger the
    # +on_mention+ callback
    #
    #   class MyBot < SlackBotServer::Bot
    #     mention_as 'hey', 'bot'
    #
    #     # etc
    #   end
    #
    # will mean the +on_mention+ callback fires for messages
    # like "hey you!" and "bot, what are you thinking".
    #
    # Mention keywords are only matched at the start of messages,
    # so the text "I love you, bot" won't trigger this callback.
    # To implement general keyword spotting, use a custom
    # +on :message+ callback.
    #
    # If this is not called, the default mention keyword is the
    # bot username, e.g. +simple_bot+
    def mention_as(*keywords)
      @mention_keywords = keywords
    end

    # Holds default options to send with each message to Slack
    def default_message_options
      @default_message_options ||= {type: 'message'}
    end

    # All callbacks defined on this class
    def callbacks
      @callbacks ||= {}
    end

    # Returns all callbacks (including those in superclasses) for a given
    # event type
    def callbacks_for(type)
      if superclass.respond_to?(:callbacks_for)
        matching_callbacks = superclass.callbacks_for(type)
      else
        matching_callbacks = []
      end
      matching_callbacks += callbacks[type.to_sym] if callbacks[type.to_sym]
      matching_callbacks
    end

    # Register a callback
    #
    #   class MyBot < SlackBotServer::Bot
    #     on :message do
    #       reply text: 'I heard a message, so now I am responding!'
    #     end
    #   end
    #
    # Possible callbacks are:
    #   +:start+ :: fires when the bot establishes a connection to Slack
    #   +:finish+ :: fires when the bot is disconnected from Slack
    #   +:message+ :: fires when any message is sent in any channel the bot is
    #                 connected to
    #
    # Multiple blocks for each type can be registered; they will be run
    # in the order they are defined.
    #
    # If any block returns +false+, later blocks will not be fired.
    def on(type, &block)
      callbacks[type.to_sym] ||= []
      callbacks[type.to_sym] << block
    end

    # Define a callback to run when any of the mention keywords are
    # present in a message.
    #
    # Typically this will be for messages in open channels, where as
    # user directs a message to this bot, e.g. "@simple_bot hello"
    #
    # By default, the mention keyword is simply the bot's username
    # e.g. +simple_bot+
    #
    # As well as the raw Slack data about the message, the data +Hash+
    # yielded to the given block will contain a +'message'+ key,
    # which holds the text sent with the keyword removed.
    def on_mention(&block)
      on(:message) do |data|
        debug on_message: data, bot_message: bot_message?(data)
        if !bot_message?(data) &&
           (data.text =~ /\A(#{mention_keywords.join('|')})[\s\:](.*)/i ||
            data.text =~ /\A(<@#{bot_user_id}>)[\s\:](.*)/)
          message = $2.strip
          @last_received_user_message.merge!(message: message)
          instance_exec(@last_received_user_message, &block)
        end
      end
    end

    # Define a callback to run when any a user sends a direct message
    # to this bot
    def on_im(&block)
      on(:message) do |data|
        debug on_im: data, bot_message: bot_message?(data), is_im_channel: is_im_channel?(data.channel)
        if !bot_message?(data) && is_im_channel?(data.channel)
          @last_received_user_message.merge!(message: data.text)
          instance_exec(@last_received_user_message, &block)
        end
      end
    end

    def low_level_callbacks
      @low_level_callbacks ||= []
    end

    # Define a callback to use when a low-level slack event is fired
    def on_slack_event(name, &block)
      self.low_level_callbacks << [name, block]
    end
  end

  on :finish do
    start if @running
  end

  # Returns a String representation of this {Bot}
  # @return String
  def to_s
    "<#{self.class.name} key:#{key}>"
  end

  private

  attr_reader :client

  def handle_message(data)
    run_callbacks(data.type, data)
  end

  def run_callbacks(type, data=nil)
    relevant_callbacks = self.class.callbacks_for(type)
    relevant_callbacks.each do |c|
      response = instance_exec(data, &c)
      break if response == false
    end
  end

  def register_low_level_callbacks
    self.class.low_level_callbacks.each do |(type, callback)|
      client.on(type) do |*args|
        begin
          instance_exec(*args, &callback)
        rescue => e
          log_error e
        end
      end
    end
  end

  def is_im_channel?(id)
    client.ims[id] != nil
  end

  def bot_message?(data)
    data.subtype == 'bot_message' ||
    data.user == SLACKBOT_USER_ID ||
    data.user == bot_user_id ||
    change_to_previous_bot_message?(data)
  end

  def change_to_previous_bot_message?(data)
    data.subtype == 'message_changed' &&
    data.previous_message.user == bot_user_id
  end

  def user_message?(data)
    !bot_message?(data) && data.subtype.nil?
  end

  def rtm_incompatible_message?(data)
    !(data[:attachments].nil? &&
      data[:username].nil? &&
      data[:icon_url].nil? &&
      data[:icon_emoji].nil? &&
      data[:channel].match(/^#/).nil?)
  end

  def default_message_options
    self.class.default_message_options
  end

  def mention_keywords
    self.class.mention_keywords || [bot_user_name]
  end

  def symbolize_keys(hash)
    hash.keys.each do |key|
      hash[key.to_sym] = hash.delete(key)
    end
    hash
  end
end
