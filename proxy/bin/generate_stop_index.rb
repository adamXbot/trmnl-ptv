#!/usr/bin/env ruby

require 'fileutils'
require 'json'
require_relative '../server'

output_path = ARGV[0]
abort 'Usage: bundle exec ruby bin/generate_stop_index.rb OUTPUT_PATH' if output_path.to_s.strip.empty?

index = GtfsStaticIndex.new
payload = {
  'generated_at' => Time.now.utc.iso8601,
  'gtfs_path' => index.gtfs_path,
  'stops' => index.stop_lookup_records
}

FileUtils.mkdir_p(File.dirname(output_path))
File.write(output_path, "#{JSON.pretty_generate(payload)}\n")

warn "[generate_stop_index] wrote #{payload['stops'].length} stops to #{output_path}"
