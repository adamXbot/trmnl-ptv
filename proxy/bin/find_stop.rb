#!/usr/bin/env ruby

require 'json'
require_relative '../server'

query = ARGV.join(' ').strip

if query.empty?
  warn 'Usage: bundle exec ruby bin/find_stop.rb "Ringwood"'
  exit 1
end

index = GtfsStaticIndex.new

puts JSON.pretty_generate(
  'query' => query,
  'gtfs_path' => index.gtfs_path,
  'matches' => index.find_stops(query)
)
