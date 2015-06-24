require 'spec_helper'

describe SlackBotServer do
  it 'has a version number' do
    expect(SlackBotServer::VERSION).not_to be nil
  end
end
