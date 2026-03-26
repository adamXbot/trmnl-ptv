require_relative '../server'

module SimpleTestHelper
  def assert(condition, message = 'assertion failed')
    raise message unless condition
  end

  def assert_equal(expected, actual, message = nil)
    return if expected == actual

    raise(message || "expected #{expected.inspect}, got #{actual.inspect}")
  end

  def refute(condition, message = 'expected condition to be false')
    raise message if condition
  end
end
