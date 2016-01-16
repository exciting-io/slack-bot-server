require 'slack_bot_server/bot'

# A simple demonstration of a bot
class SlackBotServer::SimpleBot < SlackBotServer::Bot
  # Set the username displayed in Slack
  username 'SimpleBot'

  # Respond to mentions in the connected chat room (defaults to #general).
  # As well as the normal data provided by Slack's API, we add the `message`,
  # which is the `text` parameter with the username stripped out. For example,
  # When a user sends 'simple_bot: how are you?', the `message` data contains
  # only 'how are you'.
  on_mention do |data|
    if data['message'] == 'who are you'
      reply text: "I am #{user} (id: #{user_id}), connected to team #{team} (id #{team_id})"
    else
      reply text: "You said '#{data['message']}', and I'm frankly fascinated."
    end
  end

  # Respond to messages sent via IM communication directly with the bot.
  on_im do
    reply text: "Hmm, OK, let me get back to you about that."
  end
end
