# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'slack_bot_server/version'

Gem::Specification.new do |spec|
  spec.name          = "slack-bot-server"
  spec.version       = SlackBotServer::VERSION
  spec.authors       = ["James Adam"]
  spec.email         = ["james@lazyatom.com"]

  spec.summary       = %q{A server for hosting slack bots.}
  spec.description   = %q{This software lets you write and host multiple slack bots, potentially for multiple different teams or even services.}
  spec.homepage      = "https://github.com/lazyatom/slack-bot-server"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "slack-ruby-client"
  spec.add_dependency "faye-websocket"
  spec.add_dependency "multi_json"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "redis"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "rspec-eventmachine"
  spec.add_development_dependency "yard"
end
