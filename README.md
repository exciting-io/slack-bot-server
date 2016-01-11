# SlackBotServer

[![Build Status](https://travis-ci.org/exciting-io/slack-bot-server.svg)](https://travis-ci.org/exciting-io/slack-bot-server)

If you're building an integration just for yourself, running a single bot isn't too hard and there are plenty of examples available. However, if you're building an integration for your *product* to connect with multiple teams, running multiple instances of that bot is a bit trickier.

This server is designed to hopefully make it easier to manage running bots for multiple teams at the same time, including managing their connections and adding and removing them dynamically.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'slack_bot_server'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install slack_bot_server

## Usage

To use the server in your application, you'll need to create a short script that sets up your integration and then runs the server process. Here's a simple example:

```ruby
#!/usr/bin/env ruby

require 'slack_bot_server'
require 'slack_bot_server/redis_queue'
require 'slack_bot_server/simple_bot'

# Use a Redis-based queue to add/remove bots and to trigger
# bot messages to be sent
queue = SlackBotServer::RedisQueue.new

# Create a new server using that queue
server = SlackBotServer::Server.new(queue: queue)

# How your application-specific should be created when the server
# is told about a new slack api token to connect with
server.on_add do |token|
  # Return a new bot instance to the server. `SimpleBot` is a provided
  # example bot with some very simple behaviour.
  SlackBotServer::SimpleBot.new(token: token)
end

# Actually start the server. This line is blocking; code after
# it won't be executed.
server.start
```

Running this script will start a server and keep it running; you may wish to use a tool like [Foreman](http://ddollar.github.io/foreman/) to actually start it and manage it in production.

### Writing a bot

The provided example `SimpleBot` illustrates the main ways to build a bot:

```ruby
require 'slack_bot_server/bot'

class SlackBotServer::SimpleBot < SlackBotServer::Bot
  # Set the username displayed in Slack
  username 'SimpleBot'

  # Respond to mentions in the connected chat room (defaults to #general).
  # As well as the normal data provided by Slack's API, we add the `message`,
  # which is the `text` parameter with the username stripped out. For example,
  # When a user sends 'simple_bot: how are you?', the `message` data contains
  # only 'how are you'.
  on_mention do |data|
    reply text: "You said '#{data['message']}', and I'm frankly fascinated."
  end

  # Respond to messages sent via IM communication directly with the bot.
  on_im do
    reply text: "Hmm, OK, let me get back to you about that."
  end
end
```

### Advanced example

This is a more advanced example of a server script, based on the that used by [Harmonia](https://harmonia.io), the product from which this was extracted.

```ruby
#!/usr/bin/env ruby

require 'slack_bot_server'
require 'slack_bot_server/redis_queue'
require 'harmonia/slack_bot'

# Use a Redis-based queue to add/remove bots and to trigger
# bot messages to be sent. In this case we connect to the same
# redis instance as Resque, just for convenience.
queue = SlackBotServer::RedisQueue.new(Resque.redis)

server = SlackBotServer::Server.new(queue: queue)

# The `on_add` block can take any number arguments - basically whatever
# is passed to the `add_bot` method (see below). Since the bot will almost
# certainly need to use a Slack API token to actually connect to Slack,
# this should either be one of the arguments, or be retrievable using one
# of the arguments.
# It should return a bot (something that responds to `start`); if anything
# else is returned, it will be ignored.
server.on_add do |token, team_id|
  # Our bots need to know some data about the team they are connecting
  # to, like specifics of their account and their tasks
  team_data = Harmonia.find_team_data(team_id)

  # Our bot instance stores that data in an instance variable internally
  # and then refers to it when it receives messages
  Harmonia::SlackBot.new(token: token, data: team_data)
end

# When the server starts we need to find all the teams which have already
# set up integrations and ensure their bots are launched immediately
Harmonia.teams.each do |team|
  # Any arguments can be passed to the `add_bot` method; they are passed
  # on to the proc supplied to `on_add` for the server.
  server.add_bot(team.slack_token, team.id)
end

# Actually start the server. The pre-loaded bots will connect immediately,
# and we can add new bots by sending messages using the queue.
server.start
```

### Managing bots

When someone in your application wants to connect their account with Slack, they'll need to provide a bot API token, which your application should store.

In order to actually create and connect their bot, you can use the remote
control to add the token to the server.

```ruby
# Somewhere within your application
queue = SlackBotServer::RedisQueue.new(Redis.new)
slack_remote = SlackBotServer::RemoteControl.new(queue: queue)
slack_remote.add_bot('user-accounts-slack-api-token')
```

This will queue a bot be added by the server, using the `on_add` block provided in the server script.

When a bot is created and added within the server, it is stored using a key, which the bot class itself can define, but defaults to the slack api token used to instantiate the bot.

Similarly, if a user disables their Slack integration, we should remove the bot. To remove a bot, call the `remove_bot` method on the remote using the key for the appropriate bot:

```ruby
slack_remote.remove_bot('bot-key-which-is-normally-the-slack-api-token')
```

### Getting bots to talk

Up to this point, your bots could only respond to mentions and IM messages, but it's often useful to be able to externally trigger a bot into making an announcement.

We can tell a bot to send a message into its default room fairly simply using the remote:

```ruby
slack_remote.say('bot-key', text: 'I have an important announcement to make!')
```

## Development

After checking out the repo, run `bundle` to install dependencies. Then, run `rake rspec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment. Run `bundle exec slack_bot_server` to use the gem in this directory, ignoring other installed copies of this gem.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/exciting-io/slack-bot-server.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

