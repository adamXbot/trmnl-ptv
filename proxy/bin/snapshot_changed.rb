#!/usr/bin/env ruby

require 'json'
require_relative '../server'

old_path = ARGV[0]
new_path = ARGV[1]
abort 'Usage: bundle exec ruby bin/snapshot_changed.rb OLD_JSON NEW_JSON' if old_path.to_s.strip.empty? || new_path.to_s.strip.empty?

new_payload = JSON.parse(File.read(new_path))
changed = true

if File.exist?(old_path)
  old_payload = JSON.parse(File.read(old_path))
  changed = PtvSnapshotGenerator.changed?(old_payload, new_payload)
end

puts(changed ? 'true' : 'false')
