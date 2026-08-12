class PricingRequestValidator
  VALID_PERIODS = %w[Summer Autumn Winter Spring].freeze
  VALID_HOTELS = %w[FloatingPointResort GitawayHotel RecursionRetreat].freeze
  VALID_ROOMS = %w[SingletonRoom BooleanTwin RestfulKing].freeze

  def self.validate!(params)
    new(params).validate!
  end

  def initialize(params)
    @params = params
  end

  def validate!
    return error_response("Missing required parameters: period, hotel, room") unless required_params_present?
    return error_response("Invalid period. Must be one of: #{VALID_PERIODS.join(', ')}") unless valid_period?
    return error_response("Invalid hotel. Must be one of: #{VALID_HOTELS.join(', ')}") unless valid_hotel?
    return error_response("Invalid room. Must be one of: #{VALID_ROOMS.join(', ')}") unless valid_room?

    nil
  end

  private

  def required_params_present?
    @params[:period].present? && @params[:hotel].present? && @params[:room].present?
  end

  def valid_period?
    VALID_PERIODS.include?(@params[:period])
  end

  def valid_hotel?
    VALID_HOTELS.include?(@params[:hotel])
  end

  def valid_room?
    VALID_ROOMS.include?(@params[:room])
  end

  def error_response(message)
    { error: message }
  end
end
