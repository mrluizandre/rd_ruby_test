require 'minitest/autorun'
require 'timeout'

class CustomerSuccessSameLevelError < StandardError; end
class MaxCustomerSuccessError < StandardError; end
class MaxCustomerError < StandardError; end

class CustomerSuccessBalancing
  def initialize(customer_success, customers, away_customer_success)
    @customer_success = customer_success
    @customers = customers
    @away_customer_success = away_customer_success
  end

  # Returns the ID of the customer success with most customers
  def execute
    check_constraints
    filter_css
    sort_customer_success
    balance
    count_customers
    cs_id_with_more_customers
  end

  def check_constraints
    raise CustomerSuccessSameLevelError.new "Customer Success with the same score not allowed" unless cs_scores_uniq?
    raise MaxCustomerSuccessError.new "Max customer success number of 999 reached" unless not_max_customer_success?
    raise MaxCustomerError.new "Max customers number of 999999 reached" unless not_max_customer?
  end

  def cs_scores_uniq?
    @customer_success.uniq{|c| c[:score]} == @customer_success
  end

  def not_max_customer_success?
    @customer_success.count < 1000
  end

  def not_max_customer?
    @customers.count < 1_000_000
  end

  # Get the ID of the CS with more customers on return 0 if more than one
  def cs_id_with_more_customers
    cs = @customers_by_cs.max_by{|c| c[:clients_count]}
    max_duplicate?(cs[:clients_count]) ? 0 : cs[:customer_success_id]
  end

  # Check if the CS there is only one CS with more customers
  def max_duplicate?(max)
    @customers_by_cs.select{|cbs| cbs[:clients_count] == max}.count > 1
  end

  # Count the customers by CS
  def count_customers
    @customers_by_cs = @css_available.map do |ca|
      {
        customer_success_id: ca[:id],
        clients_count: ca[:clients].count
      }
    end
  end

  # Distribute the clients by CSs matchin the criteria
  def balance
    @css_available.each_with_index do |ca, i|
      # Add the customer to CS list if he/she has same less score
      @css_available[i][:clients] = @customers.select do |c|
        c[:score] <= ca[:score]
      end
      # Remove the assigned customers from the list yet to be
      # distributed
      @customers -= @css_available[i][:clients]
    end
  end

  # Sort the CSs by score in a way the method "balance"
  # gets the less greduated first so the bigger the CS
  # the more graduated customers he/she gets
  def sort_customer_success
    @css_available = @css_available.sort_by do |ca|
      ca[:score]
    end
  end

  # Create a list with only the CSs available
  def filter_css
    @css_available = @customer_success.reject do |cs|
      @away_customer_success.include? cs[:id]
    end
  end
end

class CustomerSuccessBalancingTests < Minitest::Test
  def test_scenario_one
    balancer = CustomerSuccessBalancing.new(
      build_scores([60, 20, 95, 75]),
      build_scores([90, 20, 70, 40, 60, 10]),
      [2, 4]
    )
    assert_equal 1, balancer.execute
  end

  def test_scenario_two
    balancer = CustomerSuccessBalancing.new(
      build_scores([11, 21, 31, 3, 4, 5]),
      build_scores([10, 10, 10, 20, 20, 30, 30, 30, 20, 60]),
      []
    )
    assert_equal 0, balancer.execute
  end

  def test_scenario_three
    balancer = CustomerSuccessBalancing.new(
      build_scores(Array(1..999)),
      build_scores(Array.new(10000, 998)),
      [999]
    )
    result = Timeout.timeout(1.0) { balancer.execute }
    assert_equal 998, result
  end

  def test_scenario_four
    balancer = CustomerSuccessBalancing.new(
      build_scores([1, 2, 3, 4, 5, 6]),
      build_scores([10, 10, 10, 20, 20, 30, 30, 30, 20, 60]),
      []
    )
    assert_equal 0, balancer.execute
  end

  def test_scenario_five
    balancer = CustomerSuccessBalancing.new(
      build_scores([100, 2, 3, 6, 4, 5]),
      build_scores([10, 10, 10, 20, 20, 30, 30, 30, 20, 60]),
      []
    )
    assert_equal 1, balancer.execute
  end

  def test_scenario_six
    balancer = CustomerSuccessBalancing.new(
      build_scores([100, 99, 88, 3, 4, 5]),
      build_scores([10, 10, 10, 20, 20, 30, 30, 30, 20, 60]),
      [1, 3, 2]
    )
    assert_equal 0, balancer.execute
  end

  def test_scenario_seven
    balancer = CustomerSuccessBalancing.new(
      build_scores([100, 99, 88, 3, 4, 5]),
      build_scores([10, 10, 10, 20, 20, 30, 30, 30, 20, 60]),
      [4, 5, 6]
    )
    assert_equal 3, balancer.execute
  end

  def test_cs_same_level_exception
    balancer = CustomerSuccessBalancing.new(
      build_scores([100, 100, 88, 3, 4, 5]),
      build_scores([10, 10, 10, 20, 20, 30, 30, 30, 20, 60]),
      [4, 5, 6]
    )
    assert_raises CustomerSuccessSameLevelError do
      balancer.execute
    end
  end

  def test_number_of_cs_exception
    balancer = CustomerSuccessBalancing.new(
      build_scores(Array(1..1000)),
      build_scores([10, 10, 10, 20, 20, 30, 30, 30, 20, 60]),
      [4, 5, 6]
    )
    assert_raises MaxCustomerSuccessError do
      balancer.execute
    end
  end

  def test_number_of_customers_exception
    balancer = CustomerSuccessBalancing.new(
      build_scores([100, 99, 88, 3, 4, 5]),
      build_scores(Array(1..1_000_000)),
      [4, 5, 6]
    )
    assert_raises MaxCustomerError do
      balancer.execute
    end
  end

  private

  def build_scores(scores)
    scores.map.with_index do |score, index|
      { id: index + 1, score: score }
    end
  end
end
