require 'spec_helper'

RSpec.describe SlackBotServer::Bot do
  let(:slack_api) { double('slack api') }
  let(:im_list) { [] }
  let(:channel_list) { [{'id' => 'ABC123', 'is_member' => true}] }
  let(:bot_user_id) { 'U123456' }

  before do
    stub_websocket
    allow(::Slack::Client).to receive(:new).and_return(slack_api)
    allow(slack_api).to receive(:post).with('rtm.start').and_return({
      'ok' => true,
      'self' => {'name' => 'test_bot', 'id' => bot_user_id},
      'team' => {'name' => 'team name', 'id' => 'T123456'},
      'ims' => im_list,
      'channels' => channel_list,
      'url' => 'ws://example.dev/slack'
    })
  end

  specify "#user returns the name of the bot" do
    expect(bot_instance.user).to eq 'test_bot'
  end

  specify "#user_id returns the user id of the bot" do
    expect(bot_instance.user_id).to eq bot_user_id
  end

  specify "#team returns the team name the bot is connected to" do
    expect(bot_instance.team).to eq 'team name'
  end

  specify "#team_id returns the id of the team the bot is connected to" do
    expect(bot_instance.team_id).to eq 'T123456'
  end

  it "raises an exception if the token was rejected by slack" do
    allow(slack_api).to receive(:post).with('rtm.start').and_return({'ok' => false})
    expect { bot_instance }.to raise_error(SlackBotServer::Bot::InvalidToken)
  end

  it "allows setting the default username" do
    bot = bot_instance do
      username 'TestBot'
    end
    expect(slack_api).to receive(:chat_postMessage).with(hash_including(username: 'TestBot'))

    bot.say text: 'hello'
  end

  it "allows setting the default icon url" do
    bot = bot_instance do
      icon_url 'http://example.com/icon.png'
    end
    expect(slack_api).to receive(:chat_postMessage).with(hash_including(icon_url: 'http://example.com/icon.png'))

    bot.say text: 'hello'
  end

  it 'invokes :start callbacks after connecting' do
    check_instance = double('check')
    expect(check_instance).to receive(:call)

    bot_instance do
      on :start do
        check_instance.call
      end
    end
  end

  it 'closes websocket when stopping' do
    bot = bot_instance
    expect(stub_websocket).to receive(:close)
    bot.stop
  end

  it 'defaults the key to equal the token' do
    token = 'slack-api-token'
    bot_class = Class.new(described_class)
    bot = bot_class.new(token: token)
    expect(bot.key).to eq token
  end

  context 'sending messages' do
    let(:bot) { bot_instance }

    it "can broadcast messages to all channels" do
      expect(slack_api).to receive(:chat_postMessage).with(hash_including(channel: 'ABC123'))

      bot.broadcast text: 'hello'
    end

    it "can send a message to a specific channel" do
      expect(slack_api).to receive(:chat_postMessage).with(hash_including(channel: 'C123456'))

      bot.say channel: 'C123456', text: 'hello'
    end

    it "can send messages as DMs to a specific user" do
      expect(slack_api).to receive(:im_open).with(hash_including(user: bot_user_id)).and_return({'channel' => {'id' => 'D123'}})
      expect(slack_api).to receive(:chat_postMessage).with(hash_including(channel: 'D123', text: 'hello'))

      bot.say_to(bot_user_id, text: 'hello')
    end
  end

  describe 'handling events from Slack' do
    let(:check) { double('check') }

    it 'invokes the message handling block with the event data' do
      check_instance = check
      bot_instance do
        on :message do |message|
          check_instance.call(message)
        end
      end

      expect(check).to receive(:call).with(hash_including('text' => 'message!'))
      send_message('text' => 'message!')
    end

    it 'invokes multiple handling blocks if given' do
      check_1 = double('check 1')
      check_2 = double('check 2')
      bot_instance do
        on :message do |message|
          check_1.call(message)
        end
        on :message do |message|
          check_2.call(message)
        end
      end

      expect(check_1).to receive(:call).with(hash_including('text' => 'message!'))
      expect(check_2).to receive(:call).with(hash_including('text' => 'message!'))
      send_message('text' => 'message!')
    end

    describe "on_mention" do
      before do
        instance_check = check
        bot_instance do
          on_mention do |message|
            instance_check.call(message)
          end
        end
      end

      describe 'when name is mentioned' do
        it 'invokes on_mention blocks when username is mentioned' do
          expect(check).to receive(:call).with(hash_including('text' => 'test_bot is great'))
          send_message('text' => 'test_bot is great')
        end

        it 'extracts message without username into message parameter' do
          expect(check).to receive(:call).with(hash_including('message' => 'is great'))
          send_message('text' => 'test_bot is great')
        end

        it 'matches name in other cases' do
          expect(check).to receive(:call).with(hash_including('message' => 'is great'))
          send_message('text' => 'Test_BOT is great')
        end
      end

      describe 'when name is used in @mention' do
        it 'invokes on_mention blocks when test_bot is mentioned' do
          expect(check).to receive(:call).with(hash_including('text' => '<@U123456> is great'))
          send_message('text' => '<@U123456> is great')
        end

        it 'extracts message without username into message parameter' do
          expect(check).to receive(:call).with(hash_including('message' => 'is great'))
          send_message('text' => '<@U123456> is great')
        end
      end

      describe 'when name is not at the start of the message' do
        it 'invokes on_mention blocks when username is mentioned' do
          expect(check).not_to receive(:call)
          send_message('text' => 'I hate test_bot')
        end
      end

      it 'ignores mentions from other bots' do
        expect(check).not_to receive(:call)
        send_message('text' => 'test_bot is worse than me', 'subtype' => 'bot_message')
      end

      it 'sends replies back to the same channel' do
        instance_check = check
        bot_instance do
          on_mention do |message|
            reply text: 'hello'
          end
        end

        expect(slack_api).to receive(:chat_postMessage).with(hash_including(text: 'hello', channel: '#channel'))
        send_message('channel' => '#channel', 'text' => 'test_bot hey')
      end

      context 'when mention keywords have been specified' do
        it 'matches each word' do
          instance_check = check
          bot_instance do
            mention_as 'hey', 'dude', 'yo bot'
            on_mention do |message|
              instance_check.call(message)
            end
          end

          expect(check).to receive(:call).with(hash_including('message' => 'you'))
          send_message('text' => 'hey you')

          expect(check).to receive(:call).with(hash_including('message' => 'what?'))
          send_message('text' => 'Dude what?')

          expect(check).to receive(:call).with(hash_including('message' => 'are you there'))
          send_message('text' => 'YO BOT are you there')
        end
      end
    end

    describe "on_im" do
      let(:channel_id) { 'im123' }
      let(:im_list) { [{'id' => channel_id}] }

      before do
        instance_check = check
        bot_instance do
          on_im do |message|
            instance_check.call(message)
          end
        end
      end

      it 'invokes on_im block even without username mention' do
        expect(check).to receive(:call)
        send_message('channel' => channel_id, 'text' => 'hey you')
      end

      it 'does not invoke the block if the message is from a bot' do
        expect(check).not_to receive(:call)
        send_message('channel' => channel_id, 'text' => 'hey you', 'subtype' => 'bot_message')
      end

      it 'does not invoke the block if the message is an expansion of a message from a bot' do
        expect(check).not_to receive(:call)
        send_message('channel' => channel_id, 'subtype' => 'message_changed', 'previous_message' => {'user' => bot_user_id})
      end

      it 'does not invoke the block if the message is from SlackBot' do
        expect(check).not_to receive(:call)
        send_message('channel' => channel_id, 'user' => SlackBotServer::Bot::SLACKBOT_USER_ID)
      end

      it 'does not invoke block for messages to non-IM channels bot is in' do
        expect(check).not_to receive(:call)
        send_message('channel' => 'other123', 'text' => 'hey you')
      end

      it 'recognises new IM channels created by users' do
        send_message('type' => 'im_created', 'channel' => {'id' => 'other123'})

        expect(check).to receive(:call)
        send_message('channel' => 'other123', 'text' => 'we need to talk')
      end

      it 'sends replies back to the same channel' do
        instance_check = check
        bot_instance do
          on_im do |message|
            reply text: 'hello'
          end
        end

        expect(slack_api).to receive(:chat_postMessage).with(hash_including(text: 'hello', channel: channel_id))
        send_message('channel' => channel_id, 'text' => 'hi')
      end
    end
  end

  private

  def send_message(attributes)
    default_attributes = {'type' => 'message', 'text' => 'blah'}
    message = double('websocket message event', data: MultiJson.dump(default_attributes.merge(attributes)))
    stub_websocket.trigger(:message, message)
  end

  def bot_instance(token: 'token', key: 'key', &block)
    bot_class = Class.new(described_class, &block)
    instance = bot_class.new(token: token, key: key)
    instance.start
    stub_websocket.trigger(:open, nil)
    instance
  end

  class FakeWebsocket
    def initialize
      @callbacks = {}
    end

    def on(type, &block)
      @callbacks[type] = block
    end

    def trigger(type, event)
      @callbacks[type].call(event)
    end
  end

  def stub_websocket
    @fake ||= FakeWebsocket.new
    allow(Faye::WebSocket::Client).to receive(:new).and_return(@fake)
    @fake
  end
end
