require 'slack_bot_server/version'
require 'slack_bot_server/server'
require 'logger'

module SlackBotServer
  def self.logger
    @logger ||= Logger.new(STDOUT)
  end

  def self.logger=(logger)
    @logger = logger
  end
end

SlackBotServer.logger.level = Logger::INFO
