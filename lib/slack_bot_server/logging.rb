module SlackBotServer::Logging
  def log(*args)
    SlackBotServer.logger.info(log_string(*args))
  end

  def debug(*args)
    SlackBotServer.logger.debug(log_string(*args))
  end

  def log_error(e, *args)
    message = "ERROR: #{e} - #{e.message}"
    message += " (#{log_string(*args)})" if args.any?
    SlackBotServer.logger.warn(message)
    SlackBotServer.logger.warn(e.backtrace.join("\n"))
  end

  def log_string(*args)
    text = if args.length == 1 && args.first.is_a?(String)
      args.first
    else
      args.map { |a| a.is_a?(String) ? a : a.inspect }.join(", ")
    end
    prefix = if self.respond_to?(:bot_user_name)
      begin
        "[BOT/#{bot_user_name}]"
      rescue
        "[(BOT)/unknown]"
      end
    else
      nil
    end
    [prefix, text].join(" ")
  end
end
