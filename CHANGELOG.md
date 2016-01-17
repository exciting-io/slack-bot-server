## 0.4.1

### Changes
- Fixed detection of RTM-compatible messages

## 0.4.0

### Added
- Allow bots to send a 'typing' message
- Messages will be sent via the Real-Team API if possible (not all message parameters are acceptable there)
- Subsequent bot callbacks won't fire if an earlier one returns `false`
- `SlackBotServer::Bot` now exposes `bot_user_name`, `bot_user_id`, `team_name`, and `team_id` methods
- The logger can now be set via `SlackBotServer.logger=`
- Access the underlying Slack client via the `SlackBotServer::Bot#client` method

### Changes
- Swapped internal API library from `slack-api` to `slack-ruby-client`
- Improve internal bot logging API
- Ensure rtm data is reloaded when reconnecting
- Add missing/implicit requires to server.rb and bot.rb
- Only listen for instructions on the queue if its non-nil
- Fix bug where malformed bot key could crash when processing instructions
- Allow `SlackBotServer::RedisQueue.new` to take a custom redis key; note that this has changed the argument format of the initialiser


## 0.3.0

### Changes
- The `SlackBotServer::Server#on_new_proc` has been renamed to `Server#on_add`
- The `add` and `add_bot` methods on `SlackBotServer::Server` and `SlackBotServer::RemoteControl` control have been merged as `add_bot`
- Multiple arguments may be passed via the `add_bot` method to the block given to `SlackBotServer::on_add`
