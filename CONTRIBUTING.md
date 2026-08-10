# Contributing

## Two bundles

The repository has two independent Bundler bundles, and they are separate on purpose:

- the root [Gemfile](Gemfile), pinning `trmnl_preview` — this provides the `trmnlp` command used to
  preview and push the plugin
- [proxy/Gemfile](proxy/Gemfile), carrying `google-protobuf` and `rake` — the JSON proxy

Keeping the protobuf native extension out of the preview bundle avoids it interfering with the TRMNL
preview tooling. Run `bundle install` in whichever directory you are working in.

## Ruby version

[.ruby-version](.ruby-version) pins 3.4.8 for local work. The publish workflow installs Ruby 3.2, so
the proxy code needs to keep working on both.

## Working on the proxy

```bash
cd proxy
bundle install
PTV_KEY_ID=your_keyid bundle exec ruby server.rb
```

The proxy will download and unpack the static GTFS archive on first start if it is not already at
`PTV_GTFS_PATH`. The archive is large, so expect the first start to be slow, and expect
`proxy/data/` to appear — it is gitignored.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the endpoints, the payload shape and the full
environment variable list.

## Working on the templates

The author's local setup for the preview tooling:

```bash
brew install rbenv
brew install firefox@nightly
brew install imagemagick
rbenv init
rbenv local
bundle install
trmnlp login
trmnlp serve
trmnlp push
```

`trmnlp` comes from the [trmnl_preview](https://rubygems.org/gems/trmnl_preview) gem; check its own
documentation for current system requirements. [.trmnlp.yml](.trmnlp.yml) supplies the custom field
values used by the local preview.

## Tests

There is no test workflow, and no Rakefile. `proxy/test/` holds three plain-Ruby files, each using
the small assertion module in `test/test_helper.rb` and running itself when loaded:

```bash
cd proxy
bundle install
bundle exec ruby test/stop_lookup_test.rb
bundle exec ruby test/snapshot_payload_test.rb
bundle exec ruby test/github_action_schedule_gate_test.rb
```

They require `google-protobuf` to be installed, because `test_helper.rb` loads `server.rb`, so
`bundle install` first.

## What CI runs

The only workflow is `Publish PTV Snapshot`
([.github/workflows/publish-ptv-data.yml](.github/workflows/publish-ptv-data.yml)). On each cron tick
it installs the proxy bundle, evaluates the schedule gate, and — if the gate says yes — generates
`ptv-metro.json` and `stops.json` and pushes them to the `data` branch along with the stop finder
page. It does not run the tests and does not lint. Nothing checks a pull request automatically;
run the tests yourself before opening one.
