require 'spec_helper'

RSpec.describe SlackBotServer::Bot do
  let(:slack_api) { double('slack api', im_list: {'ims' => []}) }

  before do
    stub_websocket
    allow(::Slack::Client).to receive(:new).and_return(slack_api)
    allow(slack_api).to receive(:auth_test).and_return({'ok' => true, 'user' => 'test_bot', 'user_id' => '123456'})
    allow(slack_api).to receive(:post).with('rtm.start').and_return({'url' => 'ws://example.dev/slack'})
  end

  it "raises an exception if the token was rejected by slack" do
    allow(slack_api).to receive(:auth_test).and_return({'ok' => false})
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

  it "allows setting the default channel" do
    bot = bot_instance do
      channel '#random'
    end
    expect(slack_api).to receive(:chat_postMessage).with(hash_including(channel: '#random'))

    bot.say text: 'hello'
  end

  it "sends messages to the #general channel by default" do
    bot = bot_instance
    expect(slack_api).to receive(:chat_postMessage).with(hash_including(channel: '#general'))

    bot.say text: 'hello'
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
          expect(check).to receive(:call).with(hash_including('text' => '<@123456> is great'))
          send_message('text' => '<@123456> is great')
        end

        it 'extracts message without username into message parameter' do
          expect(check).to receive(:call).with(hash_including('message' => 'is great'))
          send_message('text' => '<@123456> is great')
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

      before do
        allow(slack_api).to receive(:im_list).and_return('ims' => [{'id' => channel_id}])

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
