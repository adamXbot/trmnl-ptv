require_relative 'test_helper'

class StopLookupTest
  include SimpleTestHelper

  def run
    test_returns_station_and_platform_matches
    test_ranks_exact_station_name_before_platforms
    puts 'stop_lookup_test: OK'
  end

  private

  def test_returns_station_and_platform_matches
    index = build_index(
      '12236' => {
        'stop_id' => '12236',
        'stop_name' => 'Ringwood Station',
        'platform_code' => '1',
        'parent_station' => 'vic:rail:RWD'
      },
      '12237' => {
        'stop_id' => '12237',
        'stop_name' => 'Ringwood Station',
        'platform_code' => '2',
        'parent_station' => 'vic:rail:RWD'
      },
      'vic:rail:RWD' => {
        'stop_id' => 'vic:rail:RWD',
        'stop_name' => 'Ringwood Railway Station'
      }
    )

    matches = index.find_stops('Ringwood')

    assert_equal(3, matches.length)
    assert_equal('12236', matches[1]['stop_id'])
    assert_equal('Platform 1', matches[1]['platform_label'])
  end

  def test_ranks_exact_station_name_before_platforms
    index = build_index(
      '12236' => {
        'stop_id' => '12236',
        'stop_name' => 'Ringwood Station',
        'platform_code' => '1',
        'parent_station' => 'vic:rail:RWD'
      },
      'vic:rail:RWD' => {
        'stop_id' => 'vic:rail:RWD',
        'stop_name' => 'Ringwood'
      }
    )

    matches = index.find_stops('Ringwood')

    assert_equal('vic:rail:RWD', matches.first['stop_id'])
    assert(matches.first['station_stop'])
  end

  def build_index(stops)
    index = GtfsStaticIndex.allocate
    index.instance_variable_set(:@stops, stops)
    index
  end
end

StopLookupTest.new.run
