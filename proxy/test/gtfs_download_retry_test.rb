require_relative 'test_helper'

class GtfsDownloadRetryTest
  include SimpleTestHelper

  def run
    test_transient_failure_is_retried_with_backoff
    test_gives_up_after_max_attempts
    test_network_errors_are_retried
    test_non_retryable_status_fails_immediately
    test_server_error_raises_retryable_error_with_truncated_body
    test_redirect_returns_location
    test_redirect_without_location_raises
    test_partial_download_is_discarded_between_attempts
    puts 'gtfs_download_retry_test: OK'
  end

  private

  def build_bootstrap(max_download_attempts: 3, slept: [])
    Dir.mktmpdir do |dir|
      return GtfsScheduleBootstrap.new(
        gtfs_path: File.join(dir, 'gtfs'),
        download_root: dir,
        zip_url: 'https://example.test/gtfs.zip',
        max_download_attempts: max_download_attempts,
        retry_sleeper: ->(seconds) { slept << seconds }
      )
    end
  end

  def build_response(klass, code, message)
    klass.new('1.1', code, message)
  end

  def test_transient_failure_is_retried_with_backoff
    slept = []
    bootstrap = build_bootstrap(slept: slept)
    attempts = 0

    bootstrap.send(:with_download_retries) do
      attempts += 1
      raise GtfsScheduleBootstrap::RetryableDownloadError, 'HTTP 500' if attempts < 3
    end

    assert_equal(3, attempts)
    assert_equal([5, 10], slept)
  end

  def test_gives_up_after_max_attempts
    slept = []
    bootstrap = build_bootstrap(max_download_attempts: 4, slept: slept)
    attempts = 0

    error = nil
    begin
      bootstrap.send(:with_download_retries) do
        attempts += 1
        raise GtfsScheduleBootstrap::RetryableDownloadError, 'HTTP 500'
      end
    rescue RuntimeError => caught
      error = caught
    end

    assert_equal(4, attempts)
    assert_equal([5, 10, 20], slept)
    assert(error, 'expected the download to fail after exhausting retries')
    assert(
      error.message.include?('failed after 4 attempts'),
      "expected attempt count in message, got: #{error.message}"
    )
  end

  def test_network_errors_are_retried
    slept = []
    bootstrap = build_bootstrap(slept: slept)
    attempts = 0

    bootstrap.send(:with_download_retries) do
      attempts += 1
      raise Errno::ECONNRESET if attempts == 1
      raise Net::ReadTimeout if attempts == 2
    end

    assert_equal(3, attempts)
    assert_equal([5, 10], slept)
  end

  def test_non_retryable_status_fails_immediately
    slept = []
    bootstrap = build_bootstrap(slept: slept)
    response = build_response(Net::HTTPNotFound, '404', 'Not Found')
    response.define_singleton_method(:body) { 'gone' }
    attempts = 0

    error = nil
    begin
      bootstrap.send(:with_download_retries) do
        attempts += 1
        bootstrap.send(:handle_download_response!, response, nil)
      end
    rescue RuntimeError => caught
      error = caught
    end

    assert_equal(1, attempts)
    assert_equal([], slept)
    assert(error, 'expected a 404 to fail the download')
    assert(
      error.message.include?('failed with 404'),
      "expected status code in message, got: #{error.message}"
    )
  end

  def test_server_error_raises_retryable_error_with_truncated_body
    bootstrap = build_bootstrap
    response = build_response(Net::HTTPInternalServerError, '500', 'Internal Server Error')
    long_body = "<html>#{'x' * 5_000}</html>"
    response.define_singleton_method(:body) { long_body }

    error = nil
    begin
      bootstrap.send(:handle_download_response!, response, nil)
    rescue GtfsScheduleBootstrap::RetryableDownloadError => caught
      error = caught
    end

    assert(error, 'expected a 500 to raise RetryableDownloadError')
    assert(
      error.message.length < 500,
      "expected the HTML error body to be truncated, message was #{error.message.length} chars"
    )
    assert(
      error.message.include?('failed with 500'),
      "expected status code in message, got: #{error.message}"
    )
  end

  def test_redirect_returns_location
    bootstrap = build_bootstrap
    response = build_response(Net::HTTPFound, '302', 'Found')
    response['location'] = 'https://cdn.example.test/gtfs.zip'

    location = bootstrap.send(:handle_download_response!, response, nil)
    assert_equal('https://cdn.example.test/gtfs.zip', location)
  end

  def test_redirect_without_location_raises
    bootstrap = build_bootstrap
    response = build_response(Net::HTTPFound, '302', 'Found')

    error = nil
    begin
      bootstrap.send(:handle_download_response!, response, nil)
    rescue RuntimeError => caught
      error = caught
    end

    assert(error, 'expected a redirect without Location to raise')
    assert(
      error.message.include?('without a Location header'),
      "unexpected message: #{error.message}"
    )
  end

  def test_partial_download_is_discarded_between_attempts
    bootstrap = build_bootstrap
    attempts = 0

    bootstrap.define_singleton_method(:fetch_zip!) do |_uri, temp, _redirects_left = nil|
      attempts += 1
      if attempts == 1
        temp.write('partial-data-from-failed-attempt')
        raise Errno::ECONNRESET
      end
      temp.write('complete-zip')
    end

    path = bootstrap.send(:download_zip!)
    assert_equal(2, attempts)
    assert_equal('complete-zip', File.read(path))
  ensure
    File.delete(path) if path && File.exist?(path)
  end
end

GtfsDownloadRetryTest.new.run
