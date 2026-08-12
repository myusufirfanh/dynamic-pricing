module PricingConfig
  module_function

  # Freshness ceiling: an entry is "fresh" while age < freshness_window (the 5-minute rule).
  def freshness_window = env_int('PRICING_FRESH_WINDOW_SECONDS', 300)

  # Max staleness servable on the degradation path; also the cache key TTL.
  def max_stale_duration = env_int('PRICING_MAX_STALE_SECONDS', 3600)

  # Single-flight lock lifetime; self-releases so a crashed winner cannot wedge the key.
  def lock_ttl_seconds = env_int('PRICING_LOCK_TTL_SECONDS', 10)

  # How long a waiter polls for the winner's refresh before degrading.
  def waiter_max_wait = env_int('PRICING_WAITER_CAP_SECONDS', 8)

  # Waiter poll cadence while waiting on the winner.
  def waiter_poll_cadence = env_float('PRICING_WAITER_POLL_INTERVAL_SECONDS', 0.1)

  # Upstream HTTP connect timeout.
  def connect_timeout = env_int('PRICING_OPEN_TIMEOUT_SECONDS', 2)

  # Upstream HTTP read timeout (bounds the in-lock wait).
  def read_timeout_seconds = env_int('PRICING_READ_TIMEOUT_SECONDS', 3)

  # Hard gate: at/after this many attempts today, skip upstream and degrade.
  def budget_hard_limit = env_int('PRICING_BUDGET_LIMIT', 100)

  def env_int(key, default) = ENV[key].present? ? Integer(ENV[key], 10) : default

  def env_float(key, default) = ENV[key].present? ? Float(ENV[key]) : default
end