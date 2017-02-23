# SlackBotServer

[![Build Status](https://travis-ci.org/exciting-io/slack-bot-server.svg)](https://travis-ci.org/exciting-io/slack-bot-server) [![Documentation](http://img.shields.io/badge/yard-docs-blue.svg)](http://www.rubydoc.info/github/exciting-io/slack-bot-server)

If you're building an integration just for yourself, running a single bot isn't too hard and there are plenty of examples available. However, if you're building an integration for your *product* to connect with multiple teams, running multiple instances of that bot is a bit trickier.

This server is designed to hopefully make it easier to manage running bots for multiple teams at the same time, including managing their connections and adding and removing them dynamically.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'slack-bot-server'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install slack-bot-server


### Optional queue stores

The default queueing mechanism uses Redis as its underlying store, but you are not tied to this - any object that has the API `#push`, `#pop` and `#clear` can be used -- and so Redis is not an explicit dependency.

However, if you are happy to use Redis (as the examples below to), you should ensure to add the `redis` gem to your `Gemfile` or your local rubygems installation.


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

If you're using Rails, I'd suggest you create your script as `bin/slack_server` (i.e. a file called `slack_server` in the `bin` directory you already have)

Running this script will start a server and keep it running; you may wish to use a tool like [Foreman](http://ddollar.github.io/foreman/) to actually start it and manage it in production. Here's a sample `Procfile`:

```
web: bundle exec rails server
slack_server: bundle exec rails runner bin/slack_server
```

By running the `bin/slack_server` script using `rails runner`, your bots get access to all the Rails models and libraries even when they are running outside of the main Rails web processes.

### Advanced server example

This is a more advanced example of a server script, based on the that used by [Harmonia][harmonia], the product from which this was extracted.

```ruby
#!/usr/bin/env ruby

require 'slack_bot_server'
require 'slack_bot_server/redis_queue'
require 'harmonia/slack_bot'

# Use a Redis-based queue to add/remove bots and to trigger
# bot messages to be sent. In this case we connect to the same
# redis instance as Resque, just for convenience.
queue = SlackBotServer::RedisQueue.new(redis: Resque.redis)

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

### Writing a bot

The provided example `SimpleBot` illustrates the main ways to build a bot:

```ruby
require 'slack_bot_server/bot'

class SlackBotServer::SimpleBot < SlackBotServer::Bot
  # Set the friendly username displayed in Slack
  username 'SimpleBot'
  # Set the image to use as an avatar icon in Slack
  icon_url 'http://my.server.example.com/assets/icon.png'

  # Respond to mentions in the connected chat room (defaults to #general).
  # As well as the normal data provided by Slack's API, we add the `message`,
  # which is the `text` parameter with the username stripped out. For example,
  # When a user sends 'simple_bot: how are you?', the `message` data contains
  # only 'how are you'.
  on_mention do |data|
    if data['message'] == 'who are you'
      reply text: "I am #{bot_user_name} (user id: #{bot_user_id}, connected to team #{team_name} with team id #{team_id}"
    else
      reply text: "You said '#{data.message}', and I'm frankly fascinated."
    end
  end

  # Respond to messages sent via IM communication directly with the bot.
  on_im do
    reply text: "Hmm, OK, let me get back to you about that."
  end
end
```

As well as the special `on_mention` and `on_im` blocks, there are a number
of other hooks that you can use when writing a bot:

* `on :message` -- will fire for every message that's received from Slack in
  the rooms that this bot is a member of
* `on :start` -- will fire when the bot establishes a connection to Slack
  (note that periodic disconnections will occur, so this hook is best used
  to gather data about the current state of Slack. You should not assume
  this is the first time the bot has ever connected)
* `on :finish` -- will fire when the bot is disconnected from Slack. This
  may be because a disconnection happened, or might be because the bot was
  removed from the server via the `remove_bot` command. You can check if
  the bot was accidentally/intermittently disconnected via the `running?`
  method, which will return true unless the bot was explicitly stopped.

## Slack App setup

As well as defining your bots in your own application, you need to tell Slack
itself about your app. You can do this at https://api.slack.com. You'll want to
create an "Installable Slack apps for any team to use".

There's some amount of documentation preamble to read, but once you follow the
prompts, you'll be asked to choose an app name and the Slack team that "owns"
this app, after which you'll be given your app _credentials_ -- a 'Client ID'
and a 'Client Secret'. You'll need these to configure your app properly.

#### OAuth setup

Still on the Slack site, you'll also need to set up your app for OAuth in order
to be able to use the 'Add to Slack' button later. Click on 'OAuth & Permissions'
in the sidebar, and then enter the urls your application runs at as valid
'Redirect URLs'.

You only really need to include the start of the URL, since a
partial match is fine. For example, for [Harmonia][harmonia] I have two URLs:

* https://harmonia.io
* http://harmonia.dev

These are the URLs for the production service, and the URL I use locally, which
lets me test things out without deploying them. The actual URL includes a longer
path component, but you don't need to include this here.

#### Add to Slack button

Here's the general form of an 'Add to Slack' button:

    <a href="https://slack.com/oauth/authorize?scope=SCOPES&client_id=CLIENT_ID.CLIENT_SECRET&redirect_uri=REDIRECT_URI">
      <img alt="Add to Slack" height="40" width="139"
           src="https://platform.slack-edge.com/img/add_to_slack.png"
           srcset="https://platform.slack-edge.com/img/add_to_slack.png 1x, https://platform.slack-edge.com/img/add_to_slack@2x.png 2x">
    </a>

Slack may change this; you can check https://api.slack.com/docs/slack-button for
their button builder if necessary.

You should replace `CLIENT_ID` and `CLIENT_SECRET` with the values you were given
when you created the app on Slack's site. `SCOPES` should be something like
`bot,team:read` (see Slack's API documentation for what these and other scopes
mean).

The `REDIRECT_URI` should be the URI to an endpoint in _your_ app where
you will intercept the Oauth request.

### OAuth endpoints in your app

It's worthwhile understanding a little about OAuth; Slack provides some good
background here: https://api.slack.com/docs/oauth

For the sake of this example, let's assume you're using Rails. Here's what a
simple OAuth setup might look like, approximately:

In `config/routes.rb`:

    get '/slack_oauth', as: 'slack_oauth', to: 'slack_controller#oauth'

In `app/controllers/slack_controller.rb`:

    class SlackController < ApplicationController
      def oauth
        if params['code']
          slack_client = Slack::Web::Client.new
          response = slack_client.oauth_access(
            code: params['code'],
            client_id: ENV['SLACK_CLIENT_ID'],
            client_secret: ENV['SLACK_CLIENT_SECRET'],
            redirect_uri: slack_oauth_url(account_id: current_account.id)
          )
          if response['ok']
            # the response object will now contain the access tokens you
            # need; something like
            #  {
            #   "access_token": "xoxp-XXXXXXXX-XXXXXXXX-XXXXX",
            #   "scope": "bot,team:read",
            #   "team_name": "Team Installing Your Bot",
            #   "team_id": "XXXXXXXXXX",
            #   "bot":{
            #       "bot_user_id":"UTTTTTTTTTTR",
            #       "bot_access_token":"xoxb-XXXXXXXXXXXX-TTTTTTTTTTTTTT"
            #   }
            # }
            # At the very least you should store the `bot_access_token` and
            # probably the `access_token` too.
            SlackIntegration.create(
              account_id: params['account_id'],
              access_token: response['access_token'],
              bot_access_token: response['bot']['bot_access_token']
            )
          else
            # there was a failure; check in the response
          end
        else
          redirect_to '/' # they cancelled adding the integration
        end
      end
    end

Here our controller responds to a request from Slack with a code, and uses that
code to obtain access tokens for the user's slack team.

You'll almost certainly want to associate the created `SlackIntegration` with
another model (e.g. an account, user or team) in your own application; I've done
this here by including the `account_id` in the redirect_uri that we send back
to Slack.

In `app/models/slack_integration.rb`:

    # Assumes a table including `access_token` and `bot_access_token` as
    # strings
    require 'slack_bot_server/remote_control'

    class SlackIntegration < ActiveRecord::Base
      after_create :add_to_slack_server

      private

      def add_to_slack_server
        queue = SlackBotServer::RedisQueue.new(redis: Redis.new)
        slack_remote = SlackBotServer::RemoteControl.new(queue: queue)
        slack_remote.add_bot(self.bot_access_token)
      end
    end

For more explanation about that last method, read on...

### Managing bots

When someone in your application wants to connect their account with Slack, they'll need to provide a bot API token, which your application should store.

In order to actually create and connect their bot, you can use the remote
control to add the token to the server.

```ruby
# Somewhere within your application
require 'slack_bot_server/remote_control'

queue = SlackBotServer::RedisQueue.new(redis: Redis.new)
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
slack_remote.say('bot-key', channel: '#general', text: 'I have an important announcement to make!')
```

## Development

After checking out the repo, run `bundle` to install dependencies. Then, run `rake rspec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment. Run `bundle exec slack_bot_server` to use the gem in this directory, ignoring other installed copies of this gem.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/exciting-io/slack-bot-server.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

[harmonia]: https://harmonia.io
