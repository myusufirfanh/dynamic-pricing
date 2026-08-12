require "test_helper"

class Api::V1::PricingControllerTest < ActionDispatch::IntegrationTest
  test "should get pricing with all parameters" do
    mock_body = {
      'rates' => [
        { 'period' => 'Summer', 'hotel' => 'FloatingPointResort', 'room' => 'SingletonRoom', 'rate' => '15000' }
      ]
    }.to_json

    RateApiClient.stub(:fetch_all!, ->(*) { mock_body }) do
      get api_v1_pricing_url, params: {
        period: "Summer",
        hotel: "FloatingPointResort",
        room: "SingletonRoom"
      }

      assert_response :success
      assert_equal "application/json", @response.media_type

      json_response = JSON.parse(@response.body)
      assert_equal "15000", json_response["rate"]
    end
  end

  test "should fetch rate from cache on second call without hitting upstream API" do
  # Clear cache to ensure clean state before starting
  Rails.cache.clear

  mock_body = {
    'rates' => [
      { 'period' => 'Summer', 'hotel' => 'FloatingPointResort', 'room' => 'SingletonRoom', 'rate' => '15000' }
    ]
  }.to_json

  # Track how many times fetch_all! is actually executed
  fetch_count = 0

  fetch_all_stub = lambda do |*args|
    fetch_count += 1
    mock_body
  end

  RateApiClient.stub(:fetch_all!, fetch_all_stub) do
    params = {
      period: "Summer",
      hotel: "FloatingPointResort",
      room: "SingletonRoom"
    }

    # --- First Call: Should hit upstream ---
    get api_v1_pricing_url, params: params
    assert_response :success
    assert_equal "15000", JSON.parse(@response.body)["rate"]
    assert_equal 1, fetch_count, "Expected upstream API to be called once on initial request"

    # --- Second Call: Should be served from Rails.cache ---
    get api_v1_pricing_url, params: params
    assert_response :success
    assert_equal "15000", JSON.parse(@response.body)["rate"]
    assert_equal 1, fetch_count, "Expected upstream API call count to remain 1 due to cache hit"
  end
end

  test "should return cached rate when budget is exhausted" do
    cached_body = {
      'rates' => [
        { 'period' => 'Summer', 'hotel' => 'FloatingPointResort', 'room' => 'SingletonRoom', 'rate' => '15000' }
      ]
    }.to_json

    RateCache.instance.instance_variable_set(:@snapshot, { RateCache::CACHE_KEY => { data: cached_body, updated_at: Time.current.to_i } })

    budget_gate = Minitest::Mock.new
    budget_gate.expect(:reserve, false)

    BudgetGate.stub(:new, budget_gate) do
      RateApiClient.stub(:fetch_all!, ->(*) { flunk "should not call upstream when budget is exhausted" }) do
        get api_v1_pricing_url, params: {
          period: "Summer",
          hotel: "FloatingPointResort",
          room: "SingletonRoom"
        }

        assert_response :success
        assert_equal "application/json", @response.media_type

        json_response = JSON.parse(@response.body)
        assert_equal "15000", json_response["rate"]
      end
    end
  end

  test "should return cached rate when downstream API fails" do
    cached_body = {
      'rates' => [
        { 'period' => 'Summer', 'hotel' => 'FloatingPointResort', 'room' => 'SingletonRoom', 'rate' => '15000' }
      ]
    }.to_json

    RateCache.instance.instance_variable_set(:@snapshot, { RateCache::CACHE_KEY => { data: cached_body, updated_at: Time.current.to_i } })

    RateApiClient.stub(:fetch_all!, ->(*) { raise RateApiClient::UpstreamError.new(kind: :server_error, status: 500) }) do
      get api_v1_pricing_url, params: {
        period: "Summer",
        hotel: "FloatingPointResort",
        room: "SingletonRoom"
      }

      assert_response :success
      assert_equal "application/json", @response.media_type

      json_response = JSON.parse(@response.body)
      assert_equal "15000", json_response["rate"]
    end
  end

  test "should return error when rate API fails and no cache exists" do
    RateCache.instance.instance_variable_set(:@snapshot, {})

    RateApiClient.stub(:fetch_all!, ->(*) { raise RateApiClient::UpstreamError.new(kind: :server_error, status: 500) }) do
      get api_v1_pricing_url, params: {
        period: "Summer",
        hotel: "FloatingPointResort",
        room: "SingletonRoom"
      }

      assert_response :bad_request
      assert_equal "application/json", @response.media_type

      json_response = JSON.parse(@response.body)
      assert_includes json_response["error"], "upstream server_error"
    end
  end

  test "should return error without any parameters" do
    get api_v1_pricing_url

    assert_response :bad_request
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_includes json_response["error"], "Missing required parameters"
  end

  test "should handle empty parameters" do
    get api_v1_pricing_url, params: {
      period: "",
      hotel: "",
      room: ""
    }

    assert_response :bad_request
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_includes json_response["error"], "Missing required parameters"
  end

  test "should reject invalid period" do
    get api_v1_pricing_url, params: {
      period: "summer-2024",
      hotel: "FloatingPointResort",
      room: "SingletonRoom"
    }

    assert_response :bad_request
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_includes json_response["error"], "Invalid period"
  end

  test "should reject invalid hotel" do
    get api_v1_pricing_url, params: {
      period: "Summer",
      hotel: "InvalidHotel",
      room: "SingletonRoom"
    }

    assert_response :bad_request
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_includes json_response["error"], "Invalid hotel"
  end

  test "should reject invalid room" do
    get api_v1_pricing_url, params: {
      period: "Summer",
      hotel: "FloatingPointResort",
      room: "InvalidRoom"
    }

    assert_response :bad_request
    assert_equal "application/json", @response.media_type

    json_response = JSON.parse(@response.body)
    assert_includes json_response["error"], "Invalid room"
  end
end
