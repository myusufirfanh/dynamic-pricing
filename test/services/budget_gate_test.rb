require "test_helper"

class BudgetGateTest < ActiveSupport::TestCase
  def setup
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  def teardown
    Rails.cache = @original_cache
  end

  test "reserve increments the counter when under the hard limit" do
    gate = BudgetGate.new

    PricingConfig.stub(:budget_hard_limit, 2) do
      assert gate.reserve
      assert_equal 1, gate.count
      assert_equal 1, gate.remaining
    end
  end

  test "reserve returns false once the hard limit is reached" do
    gate = BudgetGate.new

    PricingConfig.stub(:budget_hard_limit, 1) do
      assert gate.reserve
      assert_not gate.reserve
    end
  end
end
