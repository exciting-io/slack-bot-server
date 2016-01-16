require 'slack_bot_server/version'
require 'slack_bot_server/server'
require 'logger'

# A framework for running and controlling multiple bots. This
# is designed to make it easier for developers to provide Slack
# integration for their applications, instead of having individual
# users run their own bot instances.
module SlackBotServer
  # A Logger instance, defaulting to +INFO+ level
  def self.logger
    @logger ||= Logger.new(STDOUT)
  end

  # Assign the logger to be used by SlackBotServer
  # @param logger [Logger]
  def self.logger=(logger)
    @logger = logger
  end
end

SlackBotServer.logger.level = Logger::INFO
