require 'spec_helper'
require 'slack_bot_server/remote_control'

RSpec.describe SlackBotServer::RemoteControl do
  let(:queue) { double('queue') }
  subject { described_class.new(queue) }
  let(:token) { 'some-slack-api-token' }
  let(:key) { 'local-unique-key'}

  describe "#add_token" do
    it "pushes an 'add_token' command onto the queue with the given token" do
      expect(queue).to receive(:push).with([:add_token, token])
      subject.add_token(token)
    end
  end

  describe "#remove_bot" do
    it "pushes a 'remove_bot' command onto the queue with the given key" do
      expect(queue).to receive(:push).with([:remove_bot, key])
      subject.remove_bot(key)
    end
  end

  describe "#call" do
    it "pushes a 'call' command onto the queue with the given arguments, for the bot with the given key" do
      args = [1, 2, 3]
      expect(queue).to receive(:push).with([:call, [key, :method_name, args]])
      subject.call(key, :method_name, args)
    end
  end
end
