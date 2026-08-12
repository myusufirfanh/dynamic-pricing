class BudgetGate
  COUNTER_TTL = 48.hours

  # Defaults to the current UTC date
  def reserve(date: Time.now.utc.to_date)
    return false if limit_reached?(date: date)

    increment_counter(date: date)
    true
  rescue RedisBacked::UnavailableError, ActiveSupport::Cache::CacheError => e
    Rails.logger.error("BudgetGate: failed to reserve quota due to cache error: #{e.message}")
    # TODO: will update to actual metrics
    false
  end

  def count(date: Time.now.utc.to_date)
    Rails.cache.read(cache_key(date), raw: true).to_i
  rescue RedisBacked::UnavailableError, ActiveSupport::Cache::CacheError => e
    Rails.logger.warn("BudgetGate: failed to read counter: #{e.message}")
    # TODO: will update to actual metrics
    0
  end

  def remaining(date: Time.now.utc.to_date)
    [PricingConfig.budget_hard_limit - count(date: date), 0].max
  end

  def limit_reached?(date: Time.now.utc.to_date)
    count(date: date) >= PricingConfig.budget_hard_limit
  end

  private

  def increment_counter(date:)
    Rails.cache.increment(cache_key(date), 1, initial: 1, expires_in: COUNTER_TTL)
  end

  # Accepts a Date, Time, or ActiveSupport::TimeWithZone
  def cache_key(date)
    formatted_date = date.respond_to?(:strftime) ? date.strftime('%Y-%m-%d') : date.to_s
    "pricing:budget:#{formatted_date}"
  end
end