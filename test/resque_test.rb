require 'test_helper'

class ResqueTest < Minitest::Test

  def setup
    Resque.instance_variable_set(:@rate_limits, {})
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

    Resque.redis.expects(:scard).with("throttler:myqueue_uuids").returns(5).twice
    assert !Resque.queue_at_or_over_rate_limit?(:myqueue)
    assert !Resque.queue_at_or_over_rate_limit?("myqueue")
        
    Resque.redis.expects(:scard).with("throttler:myqueue_uuids").returns(10).twice
    assert Resque.queue_at_or_over_rate_limit?(:myqueue)
    assert Resque.queue_at_or_over_rate_limit?("myqueue")
  end

  test "Resque::pop pops on unthrottled queues" do
    Resque.redis.expects(:lpop).returns(nil)
    
    Resque.pop('myqueue')
  end
  
  test "Resque::pop skips over queues that are at or over their limit" do
    Resque.rate_limit(:myqueue, :at => 10, :per => 1)
    Resque.expects(:queue_at_or_over_rate_limit?).with("myqueue").returns(true)
    Resque.redis.expects(:lpop).never
    
    Resque.pop('myqueue')
  end

  
  test "Resque::pop gc's the limit data after skipping over a throttled queue" do
    Resque.rate_limit(:myqueue, :at => 10, :per => 1)
    Resque.expects(:queue_at_or_over_rate_limit?).with("myqueue").returns(true)
    Resque.expects(:gc_rate_limit_data_for_queue).with("myqueue").once
    
    Resque.pop('myqueue')
  end
  
  test "Resque::gc_rate_limit_data_for_queue" do
    Resque.rate_limit(:myqueue, :at => 10, :per => 5)
    Resque.redis.expects(:smembers).with("throttler:myqueue_uuids").returns(["1","2","3"]).once
    Resque.redis.expects(:srem).with("throttler:myqueue_uuids", "1").once
    Resque.redis.expects(:del).with("throttler:jobs:1").once
    
    travel_to Time.now do
      Resque.redis.expects(:hmget).with("throttler:jobs:1", "ended_at").returns((Time.now - 10).to_i)
      Resque.redis.expects(:hmget).with("throttler:jobs:2", "ended_at").returns((Time.now - 3).to_i)
      Resque.redis.expects(:hmget).with("throttler:jobs:3", "ended_at").returns(nil)
    
      Resque.gc_rate_limit_data_for_queue('myqueue')
    end
  end
  
  test "Resque::gc_rate_limit_data_for_queue for unthrottled queue" do
    Resque.gc_rate_limit_data_for_queue('myqueue')
  end
  
end