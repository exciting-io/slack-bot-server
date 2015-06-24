require 'spec_helper'
require 'slack_bot_server/local_queue'

RSpec.describe SlackBotServer::LocalQueue do
  it "returns nil when empty and pop is called" do
    expect(subject.pop).to be_nil
  end

  it "can have objects pushed on it" do
    subject.push('hello')
    expect(subject.pop).to eq 'hello'
  end

  it 'returns the first object pushed' do
    subject.push('well')
    subject.push('hello')
    expect(subject.pop).to eq 'well'
    expect(subject.pop).to eq 'hello'
  end
end
