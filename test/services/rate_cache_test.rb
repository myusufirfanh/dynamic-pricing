require "test_helper"

class RateCacheTest < ActiveSupport::TestCase
  def setup
    Rails.cache.clear
    RateCache.instance.instance_variable_set(:@snapshot, {})
  end

  test "write stores a timestamped entry and fetch returns it" do
    cache = RateCache.instance
    payload = { "rates" => [] }

    written = cache.write(payload)

    assert_equal payload, written[:data]
    assert_kind_of Integer, written[:updated_at]
    assert_equal written, cache.fetch
  end

  test "snapshot returns the last in-memory value" do
    cache = RateCache.instance
    payload = { "rates" => [] }

    cache.write(payload)
    snapshot = cache.snapshot

    assert_equal payload, snapshot[:data]
  end
end
