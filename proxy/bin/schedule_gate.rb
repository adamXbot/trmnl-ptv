#!/usr/bin/env ruby

require 'json'
require_relative '../server'

gate = GithubActionScheduleGate.from_env
payload = gate.to_h

if ENV['GITHUB_OUTPUT']
  File.open(ENV['GITHUB_OUTPUT'], 'a') do |file|
    file.puts "should_run=#{payload['should_run']}"
    file.puts "interval_minutes=#{payload['interval_minutes']}"
    file.puts "reason=#{payload['reason']}"
    file.puts "peak_window=#{payload['peak_window']}"
  end
end

puts JSON.pretty_generate(payload)
