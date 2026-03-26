require 'csv'
require 'date'
require 'fileutils'
require 'json'
require 'net/http'
require 'pathname'
require 'tmpdir'
require 'tempfile'
require 'time'
require 'uri'

require 'google/protobuf'

Google::Protobuf::DescriptorPool.generated_pool.build do
  add_file('gtfs-realtime.proto', syntax: :proto2) do
    add_enum 'transit_realtime.FeedHeader.Incrementality' do
      value :FULL_DATASET, 0
      value :DIFFERENTIAL, 1
    end

    add_enum 'transit_realtime.TripDescriptor.ScheduleRelationship' do
      value :SCHEDULED, 0
      value :ADDED, 1
      value :UNSCHEDULED, 2
      value :CANCELED, 3
      value :DUPLICATED, 5
      value :DELETED, 6
    end

    add_enum 'transit_realtime.VehiclePosition.VehicleStopStatus' do
      value :INCOMING_AT, 0
      value :STOPPED_AT, 1
      value :IN_TRANSIT_TO, 2
    end

    add_enum 'transit_realtime.VehiclePosition.CongestionLevel' do
      value :UNKNOWN_CONGESTION_LEVEL, 0
      value :RUNNING_SMOOTHLY, 1
      value :STOP_AND_GO, 2
      value :CONGESTION, 3
      value :SEVERE_CONGESTION, 4
    end

    add_enum 'transit_realtime.OccupancyStatus' do
      value :EMPTY, 0
      value :MANY_SEATS_AVAILABLE, 1
      value :FEW_SEATS_AVAILABLE, 2
      value :STANDING_ROOM_ONLY, 3
      value :CRUSHED_STANDING_ROOM_ONLY, 4
      value :FULL, 5
      value :NOT_ACCEPTING_PASSENGERS, 6
      value :NO_DATA_AVAILABLE, 7
      value :NOT_BOARDABLE, 8
    end

    add_enum 'transit_realtime.WheelchairAccessible' do
      value :NO_VALUE, 0
      value :UNKNOWN, 1
      value :WHEELCHAIR_ACCESSIBLE, 2
      value :WHEELCHAIR_INACCESSIBLE, 3
    end

    add_message 'transit_realtime.FeedMessage' do
      optional :header, :message, 1, 'transit_realtime.FeedHeader'
      repeated :entity, :message, 2, 'transit_realtime.FeedEntity'
    end

    add_message 'transit_realtime.FeedHeader' do
      required :gtfs_realtime_version, :string, 1
      optional :incrementality, :enum, 2, 'transit_realtime.FeedHeader.Incrementality'
      optional :timestamp, :uint64, 3
    end

    add_message 'transit_realtime.FeedEntity' do
      required :id, :string, 1
      optional :is_deleted, :bool, 2
      optional :vehicle, :message, 4, 'transit_realtime.VehiclePosition'
    end

    add_message 'transit_realtime.TripDescriptor' do
      optional :trip_id, :string, 1
      optional :route_id, :string, 5
      optional :direction_id, :uint32, 6
      optional :start_time, :string, 2
      optional :start_date, :string, 3
      optional :schedule_relationship, :enum, 4, 'transit_realtime.TripDescriptor.ScheduleRelationship'
    end

    add_message 'transit_realtime.VehicleDescriptor' do
      optional :id, :string, 1
      optional :label, :string, 2
      optional :license_plate, :string, 3
      optional :wheelchair_accessible, :enum, 4, 'transit_realtime.WheelchairAccessible'
    end

    add_message 'transit_realtime.Position' do
      required :latitude, :float, 1
      required :longitude, :float, 2
      optional :bearing, :float, 3
      optional :odometer, :double, 4
      optional :speed, :float, 5
    end

    add_message 'transit_realtime.VehiclePosition' do
      optional :trip, :message, 1, 'transit_realtime.TripDescriptor'
      optional :vehicle, :message, 8, 'transit_realtime.VehicleDescriptor'
      optional :position, :message, 2, 'transit_realtime.Position'
      optional :current_stop_sequence, :uint32, 3
      optional :stop_id, :string, 7
      optional :current_status, :enum, 4, 'transit_realtime.VehiclePosition.VehicleStopStatus'
      optional :timestamp, :uint64, 5
      optional :congestion_level, :enum, 6, 'transit_realtime.VehiclePosition.CongestionLevel'
      optional :occupancy_status, :enum, 9, 'transit_realtime.OccupancyStatus'
      optional :occupancy_percentage, :uint32, 10
    end
  end
end

FeedMessage = Google::Protobuf::DescriptorPool.generated_pool.lookup('transit_realtime.FeedMessage').msgclass

class GtfsScheduleBootstrap
  DEFAULT_DOWNLOAD_ROOT = File.expand_path('data/gtfs', Dir.pwd)
  DEFAULT_GTFS_PATH = File.join(DEFAULT_DOWNLOAD_ROOT, '2')
  DEFAULT_ZIP_URL = 'https://opendata.transport.vic.gov.au/dataset/3f4e292e-7f8a-4ffe-831f-1953be0fe448/resource/fb152201-859f-4882-9206-b768060b50ad/download/gtfs.zip'
  REQUIRED_FILES = %w[routes.txt stops.txt trips.txt stop_times.txt].freeze

  def initialize(
    gtfs_path: resolve_path(ENV.fetch('PTV_GTFS_PATH', DEFAULT_GTFS_PATH)),
    download_root: resolve_path(ENV.fetch('PTV_GTFS_DOWNLOAD_ROOT', DEFAULT_DOWNLOAD_ROOT)),
    zip_url: ENV.fetch('PTV_GTFS_ZIP_URL', DEFAULT_ZIP_URL)
  )
    @gtfs_path = gtfs_path
    @download_root = download_root
    @zip_url = zip_url
  end

  def ensure!
    return @gtfs_path if valid_gtfs_dir?(@gtfs_path)

    FileUtils.mkdir_p(@download_root)
    zip_path = download_zip!
    extract_zip!(zip_path)
    extract_nested_archives!
    discovered_path = discover_google_transit_dir
    raise "Unable to locate google_transit after extracting #{@zip_url}" unless discovered_path

    discovered_path
  end

  private

  def resolve_path(path)
    Pathname.new(path).absolute? ? path : File.expand_path(path, Dir.pwd)
  end

  def valid_gtfs_dir?(path)
    REQUIRED_FILES.all? { |file| File.exist?(File.join(path, file)) }
  end

  def download_zip!
    uri = URI(@zip_url)
    temp = Tempfile.new(['ptv-gtfs', '.zip'], Dir.tmpdir)
    temp.binmode

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      request = Net::HTTP::Get.new(uri)
      http.request(request) do |response|
        unless response.is_a?(Net::HTTPSuccess)
          raise "GTFS zip download failed with #{response.code}: #{response.body}"
        end

        response.read_body { |chunk| temp.write(chunk) }
      end
    end

    temp.flush
    temp.close
    temp.path
  end

  def extract_zip!(zip_path)
    success = system('unzip', '-oq', zip_path, '-d', @download_root)
    raise "Failed to unzip GTFS archive into #{@download_root}" unless success
  end

  def extract_nested_archives!
    nested_archives = Dir.glob(File.join(@download_root, '**', 'google_transit.zip'))
    nested_archives.each do |archive|
      success = system('unzip', '-oq', archive, '-d', File.dirname(archive))
      raise "Failed to unzip nested GTFS archive #{archive}" unless success
    end
  end

  def discover_google_transit_dir
    exact_match = @gtfs_path if valid_gtfs_dir?(@gtfs_path)
    return exact_match if exact_match

    parent_match = File.dirname(@gtfs_path)
    return parent_match if valid_gtfs_dir?(parent_match)

    named_candidates = Dir.glob(File.join(@download_root, '**', 'google_transit')).sort
    named_match = named_candidates.find { |candidate| valid_gtfs_dir?(candidate) }
    return named_match if named_match

    all_candidates = Dir.glob(File.join(@download_root, '**')).select { |path| File.directory?(path) }.sort
    all_candidates.find { |candidate| valid_gtfs_dir?(candidate) }
  end
end

class GtfsStaticIndex
  DEFAULT_GTFS_PATH = GtfsScheduleBootstrap::DEFAULT_GTFS_PATH
  TIMEZONE = 'Australia/Melbourne'
  LOOKAHEAD_DAYS = 2
  ROWS_PER_STOP = 2

  attr_reader :gtfs_path

  def initialize(gtfs_path = ENV.fetch('PTV_GTFS_PATH', DEFAULT_GTFS_PATH))
    @gtfs_path = gtfs_path
    @stops = {}
    @routes = {}
    @trips = {}
    @stop_times_by_trip = Hash.new { |hash, key| hash[key] = [] }
    @stop_times_by_stop = Hash.new { |hash, key| hash[key] = [] }
    @calendar_by_service = {}
    @calendar_exceptions = Hash.new { |hash, key| hash[key] = {} }
    ENV['TZ'] ||= TIMEZONE
    load_data!
  end

  def enrich_entity(entity)
    trip = entity.dig('vehicle', 'trip')
    return entity unless trip

    trip_id = trip['trip_id']
    route_id = trip['route_id']
    live_timestamp = entity.dig('vehicle', 'timestamp')
    trip_info = @trips[trip_id] || {}
    route_info = @routes[route_id] || {}
    stop_times = @stop_times_by_trip[trip_id]

    schedule = build_schedule_summary(
      trip_id: trip_id,
      trip_start_date: trip['start_date'],
      live_timestamp: live_timestamp,
      position: entity.dig('vehicle', 'position'),
      stop_times: stop_times,
      trip_info: trip_info,
      route_info: route_info
    )

    entity.merge(
      'route' => route_info,
      'trip_details' => trip_info,
      'schedule' => schedule
    )
  end

  def find_stops(query, limit: 20)
    needle = normalize_stop_text(query)
    return [] if needle.empty?

    stop_lookup_records
      .select do |stop|
        haystack = [
          stop['stop_id'],
          stop['stop_name'],
          stop['station_name'],
          stop['parent_station'],
          stop['platform_label']
        ].compact.join(' ')
        normalize_stop_text(haystack).include?(needle)
      end
      .map { |stop| stop.merge('match_score' => stop_lookup_score(stop, needle)) }
      .sort_by { |result| stop_lookup_sort_key(result) }
      .first(limit)
  end

  def stop_lookup_records
    @stops.values
      .map { |stop| build_stop_lookup_result(stop) }
      .compact
      .sort_by do |result|
        [
          result['station_name'].to_s,
          result['station_stop'] ? 0 : 1,
          result['platform_code'].to_s,
          result['stop_id'].to_s
        ]
      end
  end

  def build_display_rows(live_entities:, now: local_now)
    live_rows = Array(live_entities).map { |entity| build_live_row(entity) }.compact
    scheduled_rows = build_scheduled_rows(live_entities: live_entities, now: now)

    (live_rows + scheduled_rows).sort_by do |row|
      [
        row['display_priority'] || 99,
        row['scheduled_epoch'] || row['sort_epoch'] || 0,
        row['route_name'].to_s,
        row['stop_name'].to_s
      ]
    end
  end

  private

  def load_data!
    load_routes!
    load_stops!
    load_trips!
    load_stop_times!
    load_calendar!
    load_calendar_dates!
  end

  def csv_each(path)
    headers = nil
    CSV.foreach(path) do |row|
      if headers.nil?
        headers = row.map { |header| header.to_s.sub(/\A\xEF\xBB\xBF/, '') }
        next
      end

      values = headers.zip(row).to_h
      yield values
    end
  end

  def load_routes!
    csv_each(File.join(@gtfs_path, 'routes.txt')) do |row|
      @routes[row['route_id']] = {
        'route_id' => row['route_id'],
        'short_name' => row['route_short_name'],
        'long_name' => row['route_long_name'],
        'description' => row['route_desc'],
        'color' => row['route_color'],
        'text_color' => row['route_text_color']
      }.compact
    end
  end

  def load_stops!
    csv_each(File.join(@gtfs_path, 'stops.txt')) do |row|
      @stops[row['stop_id']] = {
        'stop_id' => row['stop_id'],
        'stop_name' => row['stop_name'],
        'lat' => row['stop_lat'].to_f,
        'lon' => row['stop_lon'].to_f,
        'platform_code' => row['platform_code'],
        'parent_station' => row['parent_station']
      }.compact
    end
  end

  def load_trips!
    csv_each(File.join(@gtfs_path, 'trips.txt')) do |row|
      @trips[row['trip_id']] = {
        'trip_id' => row['trip_id'],
        'route_id' => row['route_id'],
        'service_id' => row['service_id'],
        'headsign' => row['trip_headsign'],
        'direction_id' => row['direction_id'],
        'shape_id' => row['shape_id']
      }.compact
    end
  end

  def load_stop_times!
    csv_each(File.join(@gtfs_path, 'stop_times.txt')) do |row|
      stop_time = {
        'stop_id' => row['stop_id'],
        'trip_id' => row['trip_id'],
        'stop_sequence' => row['stop_sequence'].to_i,
        'arrival_time' => row['arrival_time'],
        'departure_time' => row['departure_time'],
        'shape_dist_traveled' => row['shape_dist_traveled'].to_f
      }
      @stop_times_by_trip[row['trip_id']] << stop_time
      @stop_times_by_stop[row['stop_id']] << stop_time
    end

    @stop_times_by_trip.each_value do |stop_times|
      stop_times.sort_by! { |stop_time| stop_time['stop_sequence'] }
    end

    @stop_times_by_stop.each_value do |stop_times|
      stop_times.sort_by! { |stop_time| stop_time['departure_time'] }
    end
  end

  def load_calendar!
    path = File.join(@gtfs_path, 'calendar.txt')
    return unless File.exist?(path)

    csv_each(path) do |row|
      @calendar_by_service[row['service_id']] = {
        'monday' => row['monday'] == '1',
        'tuesday' => row['tuesday'] == '1',
        'wednesday' => row['wednesday'] == '1',
        'thursday' => row['thursday'] == '1',
        'friday' => row['friday'] == '1',
        'saturday' => row['saturday'] == '1',
        'sunday' => row['sunday'] == '1',
        'start_date' => row['start_date'],
        'end_date' => row['end_date']
      }
    end
  end

  def load_calendar_dates!
    path = File.join(@gtfs_path, 'calendar_dates.txt')
    return unless File.exist?(path)

    csv_each(path) do |row|
      @calendar_exceptions[row['service_id']][row['date']] = row['exception_type'].to_i
    end
  end

  def build_schedule_summary(trip_id:, trip_start_date:, live_timestamp:, position:, stop_times:, trip_info:, route_info:)
    return base_schedule(trip_id, trip_info, route_info).merge('status_text' => 'No schedule data') if stop_times.nil? || stop_times.empty?
    return base_schedule(trip_id, trip_info, route_info).merge('status_text' => 'No live timestamp') if live_timestamp.nil?

    stop_times_with_epoch = stop_times.map do |stop_time|
      stop_epoch = gtfs_time_to_epoch(trip_start_date, stop_time['departure_time'])
      stop = @stops[stop_time['stop_id']] || {}
      parent_stop = stop['parent_station'] && @stops[stop['parent_station']]
      stop_time.merge(
        'scheduled_epoch' => stop_epoch,
        'scheduled_local_time' => Time.at(stop_epoch).localtime.strftime('%I:%M %P'),
        'stop_name' => stop['stop_name'],
        'platform_code' => stop['platform_code'],
        'parent_station' => stop['parent_station'],
        'station_id' => parent_stop ? parent_stop['stop_id'] : stop['stop_id'],
        'station_name' => parent_stop ? parent_stop['stop_name'] : stop['stop_name'],
        'lat' => stop['lat'],
        'lon' => stop['lon']
      )
    end

    scheduled_index = stop_times_with_epoch.rindex { |stop_time| stop_time['scheduled_epoch'] <= live_timestamp } || 0
    matched_index = choose_stop_index(stop_times_with_epoch, scheduled_index, position)
    current_stop = stop_times_with_epoch[matched_index]
    next_stop = stop_times_with_epoch[matched_index + 1]
    delay_seconds = live_timestamp - current_stop['scheduled_epoch']

    base_schedule(trip_id, trip_info, route_info).merge(
      'matched_stop_id' => current_stop['stop_id'],
      'matched_stop_name' => current_stop['stop_name'] || current_stop['stop_id'],
      'matched_stop_platform_code' => current_stop['platform_code'],
      'matched_stop_parent_station' => current_stop['parent_station'],
      'matched_stop_station_id' => current_stop['station_id'],
      'matched_stop_station_name' => current_stop['station_name'],
      'matched_stop_sequence' => current_stop['stop_sequence'],
      'scheduled_time_local' => current_stop['scheduled_local_time'],
      'scheduled_epoch' => current_stop['scheduled_epoch'],
      'delay_seconds' => delay_seconds,
      'delay_minutes' => (delay_seconds / 60.0).round,
      'status' => punctuality_status(delay_seconds),
      'status_text' => punctuality_text(delay_seconds),
      'next_stop_id' => next_stop && next_stop['stop_id'],
      'next_stop_name' => next_stop && (next_stop['stop_name'] || next_stop['stop_id']),
      'next_stop_station_id' => next_stop && next_stop['station_id'],
      'next_stop_station_name' => next_stop && next_stop['station_name'],
      'next_scheduled_time_local' => next_stop && next_stop['scheduled_local_time']
    ).compact
  end

  def base_schedule(trip_id, trip_info, route_info)
    {
      'trip_id' => trip_id,
      'headsign' => trip_info['headsign'],
      'route_name' => route_info['long_name'] || route_info['short_name'],
      'route_short_name' => route_info['short_name']
    }.compact
  end

  def choose_stop_index(stop_times, scheduled_index, position)
    return scheduled_index unless position && position['latitude'] && position['longitude']

    candidate_indexes = [
      scheduled_index - 1,
      scheduled_index,
      scheduled_index + 1,
      scheduled_index + 2
    ].select { |index| index >= 0 && index < stop_times.length }.uniq

    candidate_indexes.min_by do |index|
      stop_time = stop_times[index]
      next Float::INFINITY unless stop_time['lat'] && stop_time['lon']

      haversine_distance_m(
        position['latitude'].to_f,
        position['longitude'].to_f,
        stop_time['lat'].to_f,
        stop_time['lon'].to_f
      )
    end || scheduled_index
  end

  def gtfs_time_to_epoch(start_date, gtfs_time)
    service_date = Date.strptime(start_date, '%Y%m%d')
    hours, minutes, seconds = gtfs_time.split(':').map(&:to_i)
    local_midnight = Time.local(service_date.year, service_date.month, service_date.day, 0, 0, 0)
    local_midnight.to_i + (hours * 3600) + (minutes * 60) + seconds
  end

  def punctuality_status(delay_seconds)
    return 'on_time' if delay_seconds.abs <= 60
    return 'early' if delay_seconds < -60

    'delayed'
  end

  def punctuality_text(delay_seconds)
    return 'On time' if delay_seconds.abs <= 60
    return "#{(delay_seconds.abs / 60.0).round} min early" if delay_seconds < -60

    "#{(delay_seconds / 60.0).round} min delayed"
  end

  def haversine_distance_m(lat1, lon1, lat2, lon2)
    rad_per_deg = Math::PI / 180
    rm = 6_371_000

    dlat = (lat2 - lat1) * rad_per_deg
    dlon = (lon2 - lon1) * rad_per_deg
    lat1_rad = lat1 * rad_per_deg
    lat2_rad = lat2 * rad_per_deg

    a = Math.sin(dlat / 2)**2 + Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(dlon / 2)**2
    c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
    rm * c
  end

  def build_live_row(entity)
    vehicle = entity['vehicle']
    return nil unless vehicle

    route_id = vehicle.dig('trip', 'route_id')
    schedule = entity['schedule'] || {}
    route = entity['route'] || {}
    trip = entity['trip_details'] || {}

    {
      'kind' => 'live',
      'stop_id' => schedule['matched_stop_id'] || vehicle['stop_id'],
      'station_id' => schedule['matched_stop_station_id'] || schedule['matched_stop_parent_station'],
      'stop_name' => schedule['matched_stop_name'] || vehicle['stop_id'],
      'platform_code' => schedule['matched_stop_platform_code'],
      'route_id' => route_id,
      'route_name' => schedule['route_short_name'] || route['short_name'] || route_id,
      'headsign' => schedule['headsign'] || trip['headsign'],
      'status_text' => schedule['status_text'] || 'No live status',
      'scheduled_epoch' => schedule['scheduled_epoch'] || vehicle['timestamp'],
      'scheduled_time_local' => schedule['scheduled_time_local'],
      'sort_epoch' => vehicle['timestamp'],
      'display_priority' => 1
    }.compact
  end

  def build_scheduled_rows(live_entities:, now:)
    live_by_trip_id = Array(live_entities).each_with_object({}) do |entity, index|
      trip_id = entity.dig('vehicle', 'trip', 'trip_id')
      index[trip_id] = entity if trip_id
    end

    rows = []
    counts_by_stop = Hash.new(0)

    each_service_date(now.to_date) do |service_date|
      @stop_times_by_stop.each do |stop_id, stop_times|
        next if counts_by_stop[stop_id] >= ROWS_PER_STOP

        stop_times.each do |stop_time|
          trip_info = @trips[stop_time['trip_id']] || {}
          next unless service_active?(trip_info['service_id'], service_date)

          scheduled_epoch = gtfs_time_to_epoch(service_date.strftime('%Y%m%d'), stop_time['departure_time'])
          next if scheduled_epoch < now.to_i

          rows << build_scheduled_row(
            stop_time: stop_time,
            trip_info: trip_info,
            route_info: @routes[trip_info['route_id']] || {},
            stop: @stops[stop_id] || {},
            scheduled_epoch: scheduled_epoch,
            live_entity: live_by_trip_id[stop_time['trip_id']]
          )
          counts_by_stop[stop_id] += 1
          break if counts_by_stop[stop_id] >= ROWS_PER_STOP
        end
      end
    end

    rows
  end

  def build_scheduled_row(stop_time:, trip_info:, route_info:, stop:, scheduled_epoch:, live_entity:)
    station_id = stop['parent_station'].to_s.empty? ? stop_time['stop_id'] : stop['parent_station']
    live_status_text = live_entity && live_entity.dig('schedule', 'status_text')

    {
      'kind' => 'scheduled',
      'stop_id' => stop_time['stop_id'],
      'station_id' => station_id,
      'stop_name' => stop['stop_name'] || stop_time['stop_id'],
      'platform_code' => stop['platform_code'],
      'route_id' => trip_info['route_id'],
      'route_name' => route_info['short_name'] || route_info['long_name'] || trip_info['route_id'],
      'headsign' => trip_info['headsign'],
      'status_text' => live_status_text || "#{Time.at(scheduled_epoch).localtime.strftime('%I:%M %P')} scheduled",
      'scheduled_epoch' => scheduled_epoch,
      'scheduled_time_local' => Time.at(scheduled_epoch).localtime.strftime('%I:%M %P'),
      'sort_epoch' => scheduled_epoch,
      'display_priority' => live_status_text ? 0 : 2
    }.compact
  end

  def each_service_date(start_date)
    LOOKAHEAD_DAYS.times do |offset|
      yield(start_date + offset)
    end
  end

  def service_active?(service_id, date)
    return false if service_id.to_s.empty?

    date_key = date.strftime('%Y%m%d')
    exception_type = @calendar_exceptions[service_id][date_key]
    return true if exception_type == 1
    return false if exception_type == 2

    calendar = @calendar_by_service[service_id]
    return false unless calendar
    return false if date_key < calendar['start_date'] || date_key > calendar['end_date']

    calendar[date.strftime('%A').downcase]
  end

  def local_now
    previous_tz = ENV['TZ']
    ENV['TZ'] = TIMEZONE
    Time.now
  ensure
    ENV['TZ'] = previous_tz
  end

  def build_stop_lookup_result(stop)
    parent = parent_station_for(stop)
    station_name = parent && parent['stop_name'] != stop['stop_name'] ? parent['stop_name'] : stop['stop_name']

    {
      'stop_id' => stop['stop_id'],
      'stop_name' => stop['stop_name'],
      'station_name' => station_name,
      'platform_code' => stop['platform_code'],
      'platform_label' => platform_label(stop),
      'parent_station' => stop['parent_station'],
      'station_id' => parent ? parent['stop_id'] : stop['stop_id'],
      'station_stop' => station_record?(stop)
    }.compact
  end

  def stop_lookup_sort_key(result)
    [
      result['match_score'],
      result['station_stop'] ? 0 : 1,
      result['station_name'].to_s,
      result['platform_code'].to_s,
      result['stop_id'].to_s
    ]
  end

  def stop_lookup_score(stop, needle)
    name = normalize_stop_text(stop['stop_name'])
    parent_id = normalize_stop_text(stop['parent_station'])
    stop_id = normalize_stop_text(stop['stop_id'])
    station = normalize_stop_text(parent_station_for(stop)&.dig('stop_name'))

    return 0 if name == needle || station == needle || stop_id == needle
    return 1 if name.start_with?(needle) || station.start_with?(needle)
    return 2 if parent_id.include?(needle)

    3
  end

  def parent_station_for(stop)
    parent_id = stop['parent_station']
    return nil if parent_id.to_s.empty?

    @stops[parent_id]
  end

  def station_record?(stop)
    stop['parent_station'].to_s.empty?
  end

  def platform_label(stop)
    code = stop['platform_code'].to_s.strip
    return nil if code.empty?

    "Platform #{code}"
  end

  def normalize_stop_text(value)
    value.to_s.downcase.gsub(/[^a-z0-9]+/, ' ').strip
  end
end

class GithubActionScheduleGate
  DEFAULT_TIMEZONE = 'Australia/Melbourne'
  DEFAULT_BASE_INTERVAL_MINUTES = 15
  DEFAULT_PEAK_INTERVAL_MINUTES = 5
  DEFAULT_PEAK_START_LOCAL = '07:00'
  DEFAULT_PEAK_END_LOCAL = '09:00'
  DEFAULT_PEAK_DAYS = 'mon,tue,wed,thu,fri'

  attr_reader :timezone, :now

  def self.from_env(now: nil)
    new(
      now: now,
      timezone: ENV.fetch('TZ', DEFAULT_TIMEZONE),
      base_interval_minutes: Integer(ENV.fetch('BASE_INTERVAL_MINUTES', DEFAULT_BASE_INTERVAL_MINUTES)),
      peak_interval_minutes: Integer(ENV.fetch('PEAK_INTERVAL_MINUTES', DEFAULT_PEAK_INTERVAL_MINUTES)),
      peak_start_local: ENV.fetch('PEAK_START_LOCAL', DEFAULT_PEAK_START_LOCAL),
      peak_end_local: ENV.fetch('PEAK_END_LOCAL', DEFAULT_PEAK_END_LOCAL),
      peak_days: ENV.fetch('PEAK_DAYS', DEFAULT_PEAK_DAYS),
      force_run: env_true?(ENV['FORCE_RUN'])
    )
  end

  def self.env_true?(value)
    value.to_s.strip.downcase == 'true'
  end

  def initialize(now:, timezone:, base_interval_minutes:, peak_interval_minutes:, peak_start_local:, peak_end_local:, peak_days:, force_run: false)
    @timezone = timezone
    @now = now || current_time_in_timezone(timezone)
    @base_interval_minutes = base_interval_minutes
    @peak_interval_minutes = peak_interval_minutes
    @peak_start_local = peak_start_local
    @peak_end_local = peak_end_local
    @peak_days = parse_peak_days(peak_days)
    @force_run = force_run
  end

  def should_run?
    return true if @force_run

    (now.min % interval_minutes).zero?
  end

  def interval_minutes
    peak_window? ? @peak_interval_minutes : @base_interval_minutes
  end

  def peak_window?
    peak_day? && within_peak_time?
  end

  def peak_day?
    @peak_days.include?(day_key)
  end

  def reason
    return 'forced' if @force_run
    return "minute #{now.min} matches #{interval_minutes}-minute cadence" if should_run?

    "minute #{now.min} does not match #{interval_minutes}-minute cadence"
  end

  def to_h
    {
      'timezone' => @timezone,
      'local_day' => day_key,
      'local_time' => now.strftime('%H:%M'),
      'base_interval_minutes' => @base_interval_minutes,
      'peak_interval_minutes' => @peak_interval_minutes,
      'peak_start_local' => @peak_start_local,
      'peak_end_local' => @peak_end_local,
      'peak_days' => @peak_days,
      'peak_window' => peak_window?,
      'interval_minutes' => interval_minutes,
      'should_run' => should_run?,
      'reason' => reason,
      'force_run' => @force_run
    }
  end

  private

  def current_time_in_timezone(timezone)
    previous_tz = ENV['TZ']
    ENV['TZ'] = timezone
    Time.now
  ensure
    ENV['TZ'] = previous_tz
  end

  def parse_peak_days(value)
    normalized = value.to_s.strip.downcase
    return %w[mon tue wed thu fri] if normalized == 'weekday'
    return %w[mon tue wed thu fri sat sun] if normalized == 'daily'

    normalized.split(',').map(&:strip).reject(&:empty?)
  end

  def day_key
    now.strftime('%a').downcase[0, 3]
  end

  def within_peak_time?
    current_minutes = (now.hour * 60) + now.min
    start_minutes = parse_clock(@peak_start_local)
    end_minutes = parse_clock(@peak_end_local)
    current_minutes >= start_minutes && current_minutes < end_minutes
  end

  def parse_clock(value)
    hours, minutes = value.split(':').map(&:to_i)
    (hours * 60) + minutes
  end
end

class PtvSnapshotGenerator
  DEFAULT_PTV_URL = 'https://api.opendata.transport.vic.gov.au/opendata/public-transport/gtfs/realtime/v1/metro/vehicle-positions'

  attr_reader :gtfs_path, :auth_mode, :source_mode

  def self.stable_payload(payload)
    normalized = JSON.parse(JSON.generate(payload))
    meta = normalized['meta'] || {}
    meta.delete('generated_at')
    meta.delete('fetched_at')
    normalized['meta'] = meta
    normalized
  end

  def self.changed?(old_payload, new_payload)
    stable_payload(old_payload) != stable_payload(new_payload)
  end

  def initialize(source_mode:, cache_ttl:, schedule_context: nil)
    @source_mode = source_mode
    @cache_ttl = cache_ttl
    @schedule_context = schedule_context
    @ptv_url = ENV.fetch('PTV_METRO_VEHICLE_POSITIONS_URL', DEFAULT_PTV_URL)
    @subscription_key = ENV['PTV_SUBSCRIPTION_KEY']
    @key_id = ENV['PTV_KEY_ID']
    @gtfs_path = GtfsScheduleBootstrap.new.ensure!
    @gtfs_index = GtfsStaticIndex.new(@gtfs_path)
  end

  def generate
    generate!
  rescue StandardError => e
    warn "[ptv-snapshot] #{e.class}: #{e.message}"
    Array(e.backtrace).first(5).each { |line| warn "[ptv-snapshot] #{line}" }
    error_payload(e)
  end

  def generate!
    raise 'Set PTV_KEY_ID or PTV_SUBSCRIPTION_KEY before generating a snapshot' if auth_mode == 'missing'

    response = upstream_response
    unless response.is_a?(Net::HTTPSuccess)
      raise "PTV API request failed with #{response.code}: #{response.body}"
    end

    feed = FeedMessage.decode(response.body)
    normalized_feed = normalize_keys(feed.to_h)
    entities = Array(normalized_feed['entity']).map { |entity| @gtfs_index.enrich_entity(entity) }

    {
      'header' => normalized_feed['header'] || {},
      'entity' => entities,
      'rows' => @gtfs_index.build_display_rows(live_entities: entities),
      'meta' => base_meta.merge(
      'cache_ttl_seconds' => @cache_ttl
      )
    }
  end

  private

  def upstream_response
    uri = URI(@ptv_url)
    request = Net::HTTP::Get.new(uri)
    request['Accept'] = 'application/x-protobuf'
    request['Ocp-Apim-Subscription-Key'] = @subscription_key unless @subscription_key.to_s.strip.empty?
    request['KeyId'] = @key_id unless @key_id.to_s.strip.empty?

    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.request(request)
    end
  end

  def auth_mode
    return 'key_id' unless @key_id.to_s.strip.empty?
    return 'subscription_key' unless @subscription_key.to_s.strip.empty?

    'missing'
  end

  def base_meta
    {
      'source' => 'ptv-metro-vehicle-positions',
      'fetched_at' => Time.now.utc.iso8601,
      'generated_at' => Time.now.utc.iso8601,
      'source_mode' => @source_mode,
      'gtfs_path' => @gtfs_path,
      'auth_mode' => auth_mode,
      'upstream_url' => @ptv_url,
      'schedule_context' => @schedule_context
    }.compact
  end

  def error_payload(error)
    {
      'header' => {},
      'entity' => [],
      'meta' => base_meta.merge(
        'cache_ttl_seconds' => @cache_ttl,
        'error' => {
          'type' => error.class.name,
          'message' => error.message
        }
      )
    }
  end

  def normalize_keys(value)
    case value
    when Array
      value.map { |item| normalize_keys(item) }
    when Hash
      value.each_with_object({}) do |(key, item), result|
        result[key.to_s] = normalize_keys(item)
      end
    else
      value
    end
  end
end

class PtvVehicleProxy
  DEFAULT_PORT = 9910
  DEFAULT_CACHE_TTL = 30

  def initialize
    @port = Integer(ENV.fetch('PORT', DEFAULT_PORT))
    @cache_ttl = Integer(ENV.fetch('PTV_CACHE_TTL_SECONDS', DEFAULT_CACHE_TTL))
    @generator = PtvSnapshotGenerator.new(
      source_mode: 'local_proxy',
      cache_ttl: @cache_ttl
    )
    @cache = nil
    @cache_fetched_at = nil
    @stop_index = nil
  end

  def run
    require 'webrick'

    server = WEBrick::HTTPServer.new(
      Port: @port,
      AccessLog: [],
      Logger: WEBrick::Log.new($stderr, WEBrick::Log::INFO)
    )

    trap('INT') { server.shutdown }
    trap('TERM') { server.shutdown }

    server.mount_proc('/health') do |_req, res|
      write_json(res, 200, {
        ok: true,
        fetched_at: Time.now.utc.iso8601,
        gtfs_path: @generator.gtfs_path,
        auth_mode: @generator.auth_mode,
        source_mode: @generator.source_mode
      })
    end

    server.mount_proc('/ptv/metro/vehicle-positions') do |_req, res|
      payload = cached_payload || @generator.generate
      @cache = payload
      @cache_fetched_at = Time.now
      write_json(res, 200, payload)
    end

    server.mount_proc('/ptv/stops/search') do |req, res|
      query = req.query['q'].to_s
      matches = stop_index.find_stops(query)
      write_json(res, 200, {
        'query' => query,
        'matches' => matches,
        'gtfs_path' => stop_index.gtfs_path
      })
    end

    server.start
  end

  private

  def cached_payload
    return nil unless @cache && @cache_fetched_at
    return nil if (Time.now - @cache_fetched_at) > @cache_ttl

    @cache
  end

  def write_json(res, status, payload)
    res.status = status
    res['Content-Type'] = 'application/json'
    res.body = JSON.pretty_generate(payload)
  end

  def stop_index
    @stop_index ||= GtfsStaticIndex.new(@generator.gtfs_path)
  end
end

PtvVehicleProxy.new.run if $PROGRAM_NAME == __FILE__
