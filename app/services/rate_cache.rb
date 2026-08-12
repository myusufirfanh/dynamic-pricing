require 'securerandom'

# RateCache provides a simple Redis-backed cache with an in-memory snapshot
# for fallback when Redis is unavailable.
class RateCache
  DEFAULT_WAIT_SECONDS = PricingConfig.waiter_max_wait
  CACHE_KEY = 'rate_cache:entry'.freeze
  LOCK_KEY = 'rate_cache:lock'.freeze

  def initialize
    @snapshot = {}
    @snapshot_mutex = Mutex.new
  end

  def self.instance
    @instance ||= new
  end

  def fetch(timeout: DEFAULT_WAIT_SECONDS, &block)
    entry = read_from_cache(CACHE_KEY)
    return entry if entry.present?

    token = SecureRandom.hex(8)
    acquired = false

    begin
      acquired = acquire_lock(LOCK_KEY, token)
      unless acquired
        Rails.logger.warn("RateCache: lock busy, waiting for another refresh to complete")
        # TODO: will update to actual metrics
        wait_for_lock(LOCK_KEY, timeout)
        return read_from_cache(CACHE_KEY) || read_snapshot(CACHE_KEY)
      end

      entry = read_from_cache(CACHE_KEY)
      return entry if entry.present?

      return nil unless block_given?

      value = yield
      write(value, expires_in: PricingConfig.max_stale_duration)
    rescue => _e
      Rails.logger.warn("RateCache: cache refresh failed, falling back to snapshot: #{_e.message}")
      # TODO: will update to actual metrics
      snapshot = read_snapshot(CACHE_KEY)
      return snapshot if snapshot

      nil
    ensure
      release_lock(LOCK_KEY, token) if acquired
    end
  end

  def write(value, expires_in: PricingConfig.max_stale_duration)
    entry = { data: value, updated_at: Time.current.to_i }

    begin
      Rails.cache.write(CACHE_KEY, entry, expires_in: expires_in)
    rescue => _e
      Rails.logger.warn("RateCache: Redis write failed, keeping in-memory snapshot only: #{_e.message}")
      # TODO: will update to actual metrics
      # Keep the in-memory snapshot even if Redis write fails.
    end

    write_snapshot(CACHE_KEY, entry)
    entry
  end

  def snapshot(_key = nil)
    read_snapshot(CACHE_KEY)
  end

  private

  def acquire_lock(lock_key, token)
    Rails.cache.write(lock_key, token, unless_exist: true, expires_in: lock_ttl)
  rescue => _e
    false
  end

  def wait_for_lock(lock_key, timeout)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      begin
        return if Rails.cache.read(lock_key).nil?
      rescue => _e
        return
      end

      sleep(PricingConfig.waiter_poll_cadence)
    end
  end

  def release_lock(lock_key, token)
    return unless token

    begin
      current = Rails.cache.read(lock_key)
      return unless current == token

      Rails.cache.delete(lock_key)
    rescue => _e
      nil
    end
  end

  def lock_ttl
    if defined?(PricingConfig) && PricingConfig.respond_to?(:lock_ttl)
      PricingConfig.lock_ttl_seconds
    else
      10.seconds
    end
  end

  def read_from_cache(key)
    entry = Rails.cache.read(key)
    snapshot_entry = read_snapshot(key)

    return snapshot_entry if entry.nil? && snapshot_entry.present?
    return nil unless entry.present?

    normalized_entry = normalize_entry(entry)
    write_snapshot(key, normalized_entry)
    normalized_entry
  rescue => _e
    nil
  end

  def normalize_entry(entry)
    return entry if entry.is_a?(Hash) && entry.key?(:data) && entry.key?(:updated_at)

    { data: entry, updated_at: Time.current.to_i }
  end

  def write_snapshot(key, value)
    @snapshot_mutex.synchronize { @snapshot[key] = value }
  end

  def read_snapshot(key)
    @snapshot_mutex.synchronize { @snapshot[key] }
  end
end
