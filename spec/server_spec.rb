require 'spec_helper'
require 'rspec/em'

RSpec.describe SlackBotServer::Server do
  let(:queue) { double('queue') }
  let(:server) { described_class.new(queue: queue)}

  describe "sending instructions via the queue" do
    include RSpec::EM::FakeClock

    before { clock.stub }
    after { clock.reset }

    describe "adding a new bot via token" do
      it "calls add_token on the server with the given token" do
        expect(server).to receive(:add_token).with('token')
        enqueue_instruction :add_token, 'token'
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

  describe "#add_token" do
    it "adds the result of the new token proc" do
      bot_factory = double('bot factory')
      bot = double('bot')
      expect(bot_factory).to receive(:build).with('token').and_return(bot)
      server.on_new_token { |token| bot_factory.build(token) }
      expect(server).to receive(:add_bot).with(bot)

      server.add_token('token')
    end
  end

  describe "#add_bot" do
    let(:bot) { double('bot', key: 'key', start: nil) }

    it "starts the bot if the server is running" do
      stub_running_server
      expect(bot).to receive(:start)
      server.add_bot(bot)
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
      before { server.add_bot(bot) }

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
