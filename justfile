# List available commands
default:
    @just --list

# Install proxy dependencies
[group("dev")]
setup:
    cd proxy && bundle install

# Run the proxy test suite
[group("dev")]
test:
    cd proxy && for t in test/*_test.rb; do bundle exec ruby "$t" || exit 1; done

# Run the local JSON proxy on port 9910 (requires PTV_KEY_ID)
[group("dev")]
run:
    cd proxy && bundle exec ruby server.rb
