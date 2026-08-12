module Api::V1
  class PricingService < BaseService
    def initialize(period:, hotel:, room:)
      @period = period
      @hotel = hotel
      @room = room
    end

    def run
      attributes = [{ period: @period, hotel: @hotel, room: @room }]
      cached_entry = RateCache.instance.fetch
      if fresh_cache_entry?(cached_entry)
        @result = extract_rate_from_payload(cached_entry[:data])
        return
      end

      begin
        body = fetch_with_budget_guard(attributes: attributes)
        Rails.logger.info("PricingService: successfully fetched rates from upstream API")
        RateCache.instance.write(body, expires_in: PricingConfig.max_stale_duration)
        @result = extract_rate_from_payload(body)
      rescue RateApiClient::UpstreamError => e
        Rails.logger.warn("PricingService: upstream failure while refreshing rates: #{e.message}")
        # TODO: will update to actual metrics
        stale_entry = RateCache.instance.fetch
        if stale_entry.present?
          stale_rate = extract_rate_from_payload(stale_entry[:data])
          if stale_rate.present?
            @result = stale_rate
            return
          end
        end

        snapshot_entry = RateCache.instance.snapshot
        if snapshot_entry.present?
          Rails.logger.warn("PricingService: using snapshot fallback after upstream failure")
          # TODO: will update to actual metrics
          snapshot_rate = extract_rate_from_payload(snapshot_entry[:data])
          if snapshot_rate.present?
            @result = snapshot_rate
            return
          end
        end

        Rails.logger.error("PricingService: no usable fallback for upstream failure: #{e.message}")
        # TODO: will update to actual metrics
        errors << e.message
      end
    end

    private

    def fetch_with_budget_guard(attributes:)
      gate = BudgetGate.new
      return RateApiClient.fetch_all!(attributes: attributes) if gate.reserve

      raise RateApiClient::UpstreamError.new(kind: :budget_exhausted)
    end

    def fresh_cache_entry?(entry)
      return false unless entry.is_a?(Hash) && entry.key?(:data) && entry.key?(:updated_at)

      (Time.current.to_i - entry[:updated_at].to_i) <= PricingConfig.freshness_window
    end

    def extract_rate_from_payload(payload)
      parsed = JSON.parse(payload)
      parsed['rates'].detect { |r| r['period'] == @period && r['hotel'] == @hotel && r['room'] == @room }&.dig('rate')
    rescue JSON::ParserError, TypeError, NoMethodError
      nil
    end
  end
end
