require 'slack_bot_server/bot'

class SlackBotServer::SimpleBot < SlackBotServer::Bot
  username 'SimpleBot'

  on_mention do |data|
    reply text: "You said '#{data['message']}', and I'm frankly fascinated."
  end

  on_im do
    reply text: "Hmm, OK, let me get back to you about that."
  end
end
