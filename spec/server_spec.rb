require 'spec_helper'
require 'rspec/em'

RSpec.describe SlackBotServer::Server do
  let(:queue) { double('queue') }
  let(:server) { described_class.new(queue: queue)}

  describe "sending instructions via the queue" do
    include RSpec::EM::FakeClock

    before { clock.stub }
    after { clock.reset }

    describe "adding a new bot" do
      it "calls add_bot on the server with the given arguments" do
        expect(server).to receive(:add_bot).with('arg1', 'arg2')
        enqueue_instruction :add_bot, 'arg1', 'arg2'
        run_server
      end
    end

    describe "removing a bot from the server" do
      it "calls remove_bot on the server with the given key" do
        expect(server).to receive(:remove_bot).with('bot-key')
        enqueue_instruction :remove_bot, 'bot-key'
        run_server
      end
    end

    describe "sending a message from a bot to all channels" do
      it "calls broadcast on the bot instance matching the given key with the message data" do
        bot = double('bot')
        allow(server).to receive(:bot).with('bot-key').and_return(bot)
        expect(bot).to receive(:broadcast).with(text: 'hello')
        enqueue_instruction :broadcast, 'bot-key', text: 'hello'
        run_server
      end
    end

    describe "sending a message from a bot" do
      it "calls say on the bot instance matching the given key with the message data" do
        bot = double('bot')
        allow(server).to receive(:bot).with('bot-key').and_return(bot)
        expect(bot).to receive(:say).with(text: 'hello')
        enqueue_instruction :say, 'bot-key', text: 'hello'
        run_server
      end
    end

    describe "sending a message from a bot to a specific user" do
      it "calls say_to on the bot instance matching the given key with the message data" do
        bot = double('bot')
        allow(server).to receive(:bot).with('bot-key').and_return(bot)
        expect(bot).to receive(:say_to).with('userid', text: 'hello')
        enqueue_instruction :say_to, 'bot-key', 'userid', text: 'hello'
        run_server
      end
    end

    describe "calling an arbitrary method on a bot" do
      it "calls 'call' on the bot" do
        bot = double('bot')
        allow(server).to receive(:bot).with('bot-key').and_return(bot)
        expect(bot).to receive(:call).with('method', ['args'])
        enqueue_instruction :call, 'bot-key', 'method', ['args']
        run_server
      end
    end
  end

  describe "#add_bot" do
    let(:bot) { double('bot', key: 'key', start: nil) }
    let(:bot_factory) { double('bot factory', build: bot) }

    before do
      stub_running_server
      server.on_add { |*args| bot_factory.build(*args) }
    end

    it "builds the bot by passing the arguments to the add proc" do
      expect(bot_factory).to receive(:build).with('arg1', 'arg2').and_return(bot)

      server.add_bot('arg1', 'arg2')
    end

    it "starts the bot if the server is running" do
      expect(bot).to receive(:start)
      server.add_bot('args')
    end

    it "makes the bot available by key" do
      server.add_bot(bot)
      expect(server.bot('key')).to eq bot
    end
  end

  describe "#remove_bot" do
    it "does nothing if the bot cannot be found" do
      allow(server).to receive(:bot).with('invalid-key').and_return(nil)
      expect {
        server.remove_bot('invalid-key')
      }.not_to raise_error
    end

    describe "with a valid key" do
      let(:bot) { double('bot', key: 'key', stop: nil) }
      let(:bot_factory) { double('bot factory', build: bot) }

      before do
        server.on_add { |*args| bot_factory.build(*args) }
        server.add_bot
      end

      it "stops the bot" do
        expect(bot).to receive(:stop)
        server.remove_bot('key')
      end

      it "removes the bot" do
        server.remove_bot('key')
        expect(server.bot('key')).to be_nil
      end
    end
  end

  private

  def enqueue_instruction(*args)
    allow(queue).to receive(:pop).and_return(args)
  end

  def stub_running_server
    server.instance_eval { @running = true }
  end

  def run_server
    server.add_timers
    clock.tick(1)
  end
end
