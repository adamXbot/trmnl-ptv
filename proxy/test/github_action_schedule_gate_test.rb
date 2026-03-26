require_relative 'test_helper'

class GithubActionScheduleGateTest
  include SimpleTestHelper

  def run
    test_weekday_peak_window_uses_five_minute_cadence
    test_off_peak_uses_fifteen_minute_cadence
    test_weekend_peak_window_respects_configured_peak_days
    test_force_run_overrides_cadence
    test_dst_offsets_still_use_local_peak_window
    puts 'github_action_schedule_gate_test: OK'
  end

  private

  def build_gate(now:, peak_days: 'mon,tue,wed,thu,fri', force_run: false)
    GithubActionScheduleGate.new(
      now: now,
      timezone: 'Australia/Melbourne',
      base_interval_minutes: 15,
      peak_interval_minutes: 5,
      peak_start_local: '07:00',
      peak_end_local: '09:00',
      peak_days: peak_days,
      force_run: force_run
    )
  end

  def test_weekday_peak_window_uses_five_minute_cadence
    gate = build_gate(now: Time.new(2026, 3, 26, 7, 30, 0, '+11:00'))
    assert(gate.peak_window?)
    assert_equal(5, gate.interval_minutes)
    assert(gate.should_run?)
  end

  def test_off_peak_uses_fifteen_minute_cadence
    gate = build_gate(now: Time.new(2026, 3, 26, 10, 15, 0, '+11:00'))
    refute(gate.peak_window?)
    assert_equal(15, gate.interval_minutes)
    assert(gate.should_run?)
  end

  def test_weekend_peak_window_respects_configured_peak_days
    gate = build_gate(now: Time.new(2026, 3, 28, 7, 30, 0, '+11:00'))
    refute(gate.peak_window?)
    assert_equal(15, gate.interval_minutes)
  end

  def test_force_run_overrides_cadence
    gate = build_gate(now: Time.new(2026, 3, 26, 10, 7, 0, '+11:00'), force_run: true)
    assert(gate.should_run?)
    assert_equal('forced', gate.reason)
  end

  def test_dst_offsets_still_use_local_peak_window
    gate = build_gate(now: Time.new(2026, 7, 1, 7, 30, 0, '+10:00'))
    assert(gate.peak_window?)
    assert_equal(5, gate.interval_minutes)
  end
end

GithubActionScheduleGateTest.new.run
