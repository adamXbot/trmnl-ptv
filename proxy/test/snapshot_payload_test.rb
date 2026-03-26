require_relative 'test_helper'

class SnapshotPayloadTest
  include SimpleTestHelper

  def run
    test_changed_ignores_volatile_generation_timestamps
    test_changed_detects_real_payload_changes
    test_error_payload_has_expected_shape
    puts 'snapshot_payload_test: OK'
  end

  private

  def test_changed_ignores_volatile_generation_timestamps
    old_payload = {
      'header' => { 'timestamp' => 123 },
      'entity' => [{ 'id' => 'a' }],
      'meta' => {
        'generated_at' => '2026-03-26T00:00:00Z',
        'fetched_at' => '2026-03-26T00:00:00Z',
        'source_mode' => 'github_action'
      }
    }
    new_payload = {
      'header' => { 'timestamp' => 123 },
      'entity' => [{ 'id' => 'a' }],
      'meta' => {
        'generated_at' => '2026-03-26T00:05:00Z',
        'fetched_at' => '2026-03-26T00:05:00Z',
        'source_mode' => 'github_action'
      }
    }

    refute(PtvSnapshotGenerator.changed?(old_payload, new_payload))
  end

  def test_changed_detects_real_payload_changes
    old_payload = {
      'header' => { 'timestamp' => 123 },
      'entity' => [{ 'id' => 'a' }],
      'meta' => { 'generated_at' => '2026-03-26T00:00:00Z' }
    }
    new_payload = {
      'header' => { 'timestamp' => 124 },
      'entity' => [{ 'id' => 'a' }],
      'meta' => { 'generated_at' => '2026-03-26T00:05:00Z' }
    }

    assert(PtvSnapshotGenerator.changed?(old_payload, new_payload))
  end

  def test_error_payload_has_expected_shape
    generator = PtvSnapshotGenerator.allocate
    generator.instance_variable_set(:@source_mode, 'github_action')
    generator.instance_variable_set(:@cache_ttl, 30)
    generator.instance_variable_set(:@schedule_context, { 'interval_minutes' => 15 })
    generator.instance_variable_set(:@ptv_url, 'https://example.test/vehicle-positions')
    generator.instance_variable_set(:@gtfs_path, '/tmp/gtfs')
    generator.instance_variable_set(:@subscription_key, nil)
    generator.instance_variable_set(:@key_id, 'abc')

    payload = generator.send(:error_payload, RuntimeError.new('boom'))

    assert_equal({}, payload['header'])
    assert_equal([], payload['entity'])
    assert_equal('boom', payload.dig('meta', 'error', 'message'))
    assert_equal('github_action', payload.dig('meta', 'source_mode'))
    assert_equal('/tmp/gtfs', payload.dig('meta', 'gtfs_path'))
  end
end

SnapshotPayloadTest.new.run
