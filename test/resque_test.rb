require 'test_helper'

class ResqueTest < Minitest::Test

  def setup
    Resque.instance_variable_set(:@rate_limits, {})
    @redis = Redis::Namespace.new(:resque, redis: Redis.new)
    Resque.redis = @redis
  end

  test "Resque::rate_limit" do
    Resque.rate_limit(:myqueue, :at => 10, :per => 1)

    assert_equal Resque.instance_variable_get(:@rate_limits), {
      'myqueue' => {:at => 10, :per => 1}
    }
  end

  test "Resque::queue_rate_limited?" do
    Resque.rate_limit(:myqueue, :at => 10, :per => 1)

    assert Resque.queue_rate_limited?(:myqueue)
    assert Resque.queue_rate_limited?("myqueue")
  end

  test "Resque::queue_at_or_over_rate_limit?" do
    Resque.rate_limit(:myqueue, :at => 10, :per => 1)

    @redis.expects(:scard).with("throttler:myqueue_uuids").returns(5).twice
    assert !Resque.queue_at_or_over_rate_limit?(:myqueue)
    assert !Resque.queue_at_or_over_rate_limit?("myqueue")

    @redis.expects(:scard).with("throttler:myqueue_uuids").returns(10).twice
    assert Resque.queue_at_or_over_rate_limit?(:myqueue)
    assert Resque.queue_at_or_over_rate_limit?("myqueue")
  end

  test "Resque::pop pops on unthrottled queues" do
    @redis.expects(:lpop).returns(nil)

    Resque.pop('myqueue')
  end

  test "Resque::pop skips over queues that are at or over their limit" do
    Resque.rate_limit(:myqueue, :at => 10, :per => 1)
    Resque.expects(:queue_at_or_over_rate_limit?).with("myqueue").returns(true)
    @redis.expects(:lpop).never

    Resque.pop('myqueue')
  end


  test "Resque::pop gc's the limit data after skipping over a throttled queue" do
    Resque.rate_limit(:myqueue, :at => 10, :per => 1)
    Resque.expects(:queue_at_or_over_rate_limit?).with("myqueue").returns(true)
    Resque.expects(:gc_rate_limit_data_for_queue).with("myqueue").once

    Resque.pop('myqueue')
  end

  test "Resque::pop does not gc the limit data if killswitched" do
    begin
      Resque.perform_inline_rate_limit_gc = false
      Resque.rate_limit(:myqueue, :at => 10, :per => 1)
      Resque.expects(:queue_at_or_over_rate_limit?).with("myqueue").returns(true)
      Resque.expects(:gc_rate_limit_data_for_queue).with("myqueue").never

      Resque.pop('myqueue')
    ensure
      Resque.perform_inline_rate_limit_gc = true
    end
  end

  test "Resque::gc_rate_limit_data_for_queue" do
    Resque.rate_limit(:myqueue, :at => 10, :per => 5, :max_duration => 300)
    @redis.expects(:smembers).with("throttler:myqueue_uuids").returns(["1","2","3","4","5"]).once
    @redis.expects(:srem).with("throttler:myqueue_uuids", "1").once
    @redis.expects(:del).with("throttler:jobs:1").once

    @redis.expects(:srem).with("throttler:myqueue_uuids", "4").once
    @redis.expects(:del).with("throttler:jobs:4").once

    @redis.expects(:srem).with("throttler:myqueue_uuids", "5").once
    @redis.expects(:del).with("throttler:jobs:5").once

    travel_to Time.now do
      @redis.expects(:hgetall).with("throttler:jobs:1").returns({ 'started_at' => Time.now - 20, 'ended_at' => Time.now - 10 })
      @redis.expects(:hgetall).with("throttler:jobs:2").returns({ 'started_at' => Time.now - 20, 'ended_at' => Time.now - 3 })
      @redis.expects(:hgetall).with("throttler:jobs:3").returns({ 'started_at' => Time.now - 20, 'ended_at' => nil })
      @redis.expects(:hgetall).with("throttler:jobs:4").returns({ 'started_at' => Time.now - 310, 'ended_at' => nil })
      @redis.expects(:hgetall).with("throttler:jobs:5").returns({})

      Resque.gc_rate_limit_data_for_queue('myqueue')
    end
  end

  test "Resque::gc_rate_limit_data_for_queue for unthrottled queue" do
    Resque.gc_rate_limit_data_for_queue('myqueue')
  end

end
