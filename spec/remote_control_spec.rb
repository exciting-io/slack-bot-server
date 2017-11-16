require 'spec_helper'
require 'slack_bot_server/remote_control'

RSpec.describe SlackBotServer::RemoteControl do
  let(:queue) { double('queue') }
  subject { described_class.new(queue: queue) }
  let(:key) { 'local-unique-key'}

  describe "#add_bot" do
    it "pushes an 'add_bot' command onto the queue with the given arguments" do
      expect(queue).to receive(:push).with([:add_bot, 'arg1', 'arg2', 'arg3'])
      subject.add_bot('arg1', 'arg2', 'arg3')
    end
  end

  describe "#remove_bot" do
    it "pushes a 'remove_bot' command onto the queue with the given key" do
      expect(queue).to receive(:push).with([:remove_bot, key])
      subject.remove_bot(key)
    end
  end

  describe "#say" do
    it "pushes a 'send_message' command onto the queue with the given key and message data" do
      expect(queue).to receive(:push).with([:say, key, {text: 'hello'}])
      subject.say(key, text: 'hello')
    end
  end

  describe "#broadcast" do
    it "pushes a 'send_message' command onto the queue with the given key and message data" do
      expect(queue).to receive(:push).with([:broadcast, key, {text: 'hello'}])
      subject.broadcast(key, text: 'hello')
    end
  end

  describe "#say_to" do
    it "pushes a 'send_message' command onto the queue with the given key and message data" do
      expect(queue).to receive(:push).with([:say_to, key, 'userid', {text: 'hello'}])
      subject.say_to(key, 'userid', text: 'hello')
    end
  end

  describe "#update" do
    it "pushes a 'update' command onto the queue with the given key and message data" do
      expect(queue).to receive(:push).with([:update, key, {text: 'hello'}])
      subject.update(key, text: 'hello')
    end
  end

  describe "#call" do
    it "pushes a 'call' command onto the queue with the given arguments, for the bot with the given key" do
      args = [1, 2, 3]
      expect(queue).to receive(:push).with([:call, key, :method_name, args])
      subject.call(key, :method_name, args)
    end
  end
end
