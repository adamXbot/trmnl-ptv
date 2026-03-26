#!/usr/bin/env ruby

require 'fileutils'
require 'json'
require_relative '../server'

output_path = ARGV[0]
abort 'Usage: bundle exec ruby bin/generate_snapshot.rb OUTPUT_PATH' if output_path.to_s.strip.empty?

gate_context = nil
if ENV.fetch('PTV_SOURCE_MODE', 'github_action') == 'github_action'
  full_gate_context = GithubActionScheduleGate.from_env.to_h
  gate_context = {
    'timezone' => full_gate_context['timezone'],
    'base_interval_minutes' => full_gate_context['base_interval_minutes'],
    'peak_interval_minutes' => full_gate_context['peak_interval_minutes'],
    'peak_start_local' => full_gate_context['peak_start_local'],
    'peak_end_local' => full_gate_context['peak_end_local'],
    'peak_days' => full_gate_context['peak_days']
  }
end

generator = PtvSnapshotGenerator.new(
  source_mode: ENV.fetch('PTV_SOURCE_MODE', 'github_action'),
  cache_ttl: Integer(ENV.fetch('PTV_CACHE_TTL_SECONDS', PtvVehicleProxy::DEFAULT_CACHE_TTL)),
  schedule_context: gate_context
)

payload = generator.generate
FileUtils.mkdir_p(File.dirname(output_path))
File.write(output_path, "#{JSON.pretty_generate(payload)}\n")

if (error = payload.dig('meta', 'error'))
  warn "[generate_snapshot] wrote error payload: #{error['type']}: #{error['message']}"
else
  warn "[generate_snapshot] wrote snapshot to #{output_path}"
end
