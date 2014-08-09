require 'test_helper'

class MyJob
  def self.perform
  end
end

class MyErrorJob
  def self.perform
    raise ArgumentError
  end
end

class Resque::JobTest < Minitest::Test

  def setup
    Resque.instance_variable_set(:@rate_limits, {})
  end

  test 'Resque::Job::initialize sets up @throttled and @throttler_uuid' do
    SecureRandom.expects(:uuid).returns("jobuuid").twice
    Resque.rate_limit(:myqueue, :at => 10, :per => 1)
        
    job = Resque::Job.new(:other_queue, { 'class' => 'MyJob', 'args'  => [] })
    assert_equal 'jobuuid', job.instance_variable_get(:@throttler_uuid)
    assert_equal  false,    job.instance_variable_get(:@throttled)
          
          

    job = Resque::Job.new(:myqueue, { 'class' => 'MyJob', 'args'  => [] })
    assert_equal 'jobuuid', job.instance_variable_get(:@throttler_uuid)
    assert_equal  true,     job.instance_variable_get(:@throttled)
  end
  
  test "Resque::Job::perform on unthrottled job" do
    Resque.rate_limit(:myqueue, :at => 10, :per => 1)

    job = Resque::Job.new(:other_queue, {
      'class' => 'MyJob',
      'args'  => []
    })
    
    travel_to Time.now do
      SecureRandom.expects(:uuid).returns("jobuuid").never
      Resque.redis.expects(:hmset).with("throttler:jobs:jobuuid", "started_at", Time.now.to_i).never
      Resque.redis.expects(:sadd).with("throttler:myqueue_uuids", "jobuuid").never
      Resque.redis.expects(:hmset).with("throttler:jobs:jobuuid", "ended_at", Time.now.to_i).never
      
      job.perform
    end
  end
    
  test "Resque::Job::perform on throttled job" do
    SecureRandom.expects(:uuid).returns("jobuuid")
    Resque.rate_limit(:myqueue, :at => 10, :per => 1)

    job = Resque::Job.new(:myqueue, {
      'class' => 'MyJob',
      'args'  => []
    })
    
    travel_to Time.now do
      Resque.redis.expects(:hmset).with("throttler:jobs:jobuuid", "started_at", Time.now.to_i).once
      Resque.redis.expects(:sadd).with("throttler:myqueue_uuids", "jobuuid").once
      Resque.redis.expects(:hmset).with("throttler:jobs:jobuuid", "ended_at", Time.now.to_i).once
      
      job.perform
    end
  end
  
  test "Resque::Job::perform on throttled job with job that throws error" do
    SecureRandom.expects(:uuid).returns("jobuuid")
    Resque.rate_limit(:myqueue, :at => 10, :per => 1)

    job = Resque::Job.new('myqueue', {
      'class' => 'MyErrorJob',
      'args'  => []
    })

    travel_to Time.now do
      Resque.redis.expects(:hmset).with("throttler:jobs:jobuuid", "started_at", Time.now.to_i).once
      Resque.redis.expects(:sadd).with("throttler:myqueue_uuids", "jobuuid").once
      Resque.redis.expects(:hmset).with("throttler:jobs:jobuuid", "ended_at", Time.now.to_i).once

      assert_raises(ArgumentError) {
        job.perform
      }
    end
  end
  
end

