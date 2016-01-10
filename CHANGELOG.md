## 0.3.0

Changes:

  - The `SlackBotServer::Server#on_new_proc` has been renamed to `Server#on_add`
  - The `add` and `add_bot` methods on `SlackBotServer::Server` and `SlackBotServer::RemoteControl` control have been merged as `add_bot`
  - Multiple arguments may be passed via the `add_bot` method to the block given to `SlackBotServer::on_add`
