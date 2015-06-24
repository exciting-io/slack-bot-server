$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'slack_bot_server'

SlackBotServer.logger.level = Logger::ERROR
