class RateApiClient
  include HTTParty

  base_uri ENV.fetch('RATE_API_URL', 'http://localhost:8080')
  headers 'Content-Type' => 'application/json'

  # Raised for every upstream transport failure (timeout, connection, non-2xx, error envelope).
  class UpstreamError < StandardError
    attr_reader :kind, :status

    def initialize(kind:, status: nil)
      @kind = kind
      @status = status
      super("upstream #{kind}#{" (HTTP #{status})" if status}")
    end
  end

  class << self

    # Batch fetch: POSTs all requested combinations in one call and returns the raw 2xx body.
    def fetch_all!(attributes:, open_timeout: PricingConfig.connect_timeout, read_timeout: PricingConfig.read_timeout_seconds)
      response = post(
        '/pricing',
        headers: auth_headers,
        body: { attributes: attributes }.to_json,
        open_timeout: open_timeout,
        read_timeout: read_timeout
      )

      unless response.success?
        raise UpstreamError.new(kind: status_kind(response.code), status: response.code)
      end

      if error_envelope?(response.body)
        raise UpstreamError.new(kind: :error_response, status: response.code)
      end

      response.body
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error
      raise UpstreamError.new(kind: :timeout)
    rescue SocketError, SystemCallError, HTTParty::Error
      raise UpstreamError.new(kind: :connection)
    end

    private

    def auth_headers
      token = ENV['RATE_API_TOKEN']
      raise "RATE_API_TOKEN environment variable is not set" if token.nil? || token.empty?

      { 'token' => token }
    end

    def status_kind(code)
      case code
      when 401, 403 then :unauthorized
      when 429      then :rate_limited
      when 500..599 then :server_error
      else               :unexpected_status
      end
    end

    def error_envelope?(body)
      parsed = JSON.parse(body)
      parsed.is_a?(Hash) && parsed['status'] == 'error'
    rescue JSON::ParserError
      false
    end

  end
end