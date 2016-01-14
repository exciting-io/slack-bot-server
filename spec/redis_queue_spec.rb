require 'spec_helper'

RSpec.describe SlackBotServer::RedisQueue do
  let(:queue_key) { 'slack_bot_server:queue' }
  let(:redis) { double('redis') }
  subject { described_class.new(redis: redis) }

  it "will default to the default Redis connection if none is given" do
    redis_class = Class.new
    stub_const("Redis", redis_class)
    expect(redis_class).to receive(:new).and_return(redis)
    described_class.new()
  end

  it "allows specification of a custom key" do
    queue = described_class.new(redis: redis, key: 'custom-key')

    allow(MultiJson).to receive(:dump).and_return('json-value')
    expect(redis).to receive(:rpush).with('custom-key', 'json-value')

    queue.push('some value')
  end

  describe "#push" do
    it "pushes json value onto the right of the list" do
      object = Object.new
      allow(MultiJson).to receive(:dump).with(object).and_return('json-value')
      expect(redis).to receive(:rpush).with(queue_key, 'json-value')

      subject.push(object)
    end
  end

  describe "#pop" do
    context "when queue is empty" do
      before { allow(redis).to receive(:lpop).with(queue_key).and_return(nil) }

      it "returns nil" do
        expect(subject.pop).to be_nil
      end
    end

    context "when queue has an item" do
      it "returns JSON-decoded object" do
        object = Object.new
        allow(MultiJson).to receive(:load).with('json-value', symbolize_keys: true).and_return(object)
        expect(redis).to receive(:lpop).with(queue_key).and_return('json-value')

        expect(subject.pop).to eq object
      end
    end
  end
end
