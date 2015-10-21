require 'resque'
require 'securerandom'

module Resque::Plugins
  module Throttler
    extend self
  
    def self.extended(other)
      other.instance_variable_set(:@rate_limits, {})
    end
  
    def pop(queue)
      if queue_at_or_over_rate_limit?(queue)
        gc_rate_limit_data_for_queue(queue)
        nil
      else
        super
      end
    end

    def rate_limit(queue, options={})
      if options.keys.sort != [:at, :per]
        raise ArgumentError.new("Mising either :at or :per in options") 
      end
    
      @rate_limits[queue.to_s] = options
    end
  
    def rate_limit_for(queue)
      @rate_limits[queue.to_s]
    end
  
    def queue_rate_limited?(queue)
      !!@rate_limits[queue.to_s]
    end
  
    def queue_at_or_over_rate_limit?(queue)
      if queue_rate_limited?(queue)
        redis.scard("throttler:#{queue}_uuids") >= rate_limit_for(queue)[:at]
      else
        false
      end
    end
  
    def gc_rate_limit_data_for_queue(queue)
      return unless queue_rate_limited?(queue)
    
      limit = rate_limit_for(queue)
      queue_key = "throttler:#{queue}_uuids"
      uuids = redis.smembers(queue_key)
    
      uuids.each do |uuid|
        job_ended_at = redis.hmget("throttler:jobs:#{uuid}", "ended_at")[0]
        if job_ended_at && Time.at(job_ended_at.to_i) < Time.now - limit[:per]
          redis.srem(queue_key, uuid)
          redis.del("throttler:jobs:#{uuid}")
        end
      end
    end
    
  end
end

Resque.extend(Resque::Plugins::Throttler)

class Resque::Job
  
  def initialize_with_throttler(queue, payload)
    @throttled = Resque.queue_rate_limited?(queue)
    @throttler_uuid = SecureRandom.uuid
    initialize_without_throttler(queue, payload)
  end
  alias_method :initialize_without_throttler, :initialize
  alias_method :initialize, :initialize_with_throttler
  
  def perform_with_throttler
    if @throttled
      begin
        redis.multi do
          redis.hmset("throttler:jobs:#{@throttler_uuid}", "started_at", Time.now.to_i)
          redis.sadd("throttler:#{queue}_uuids", @throttler_uuid)
        end
        perform_without_throttler
      ensure
        redis.hmset("throttler:jobs:#{@throttler_uuid}", "ended_at", Time.now.to_i)
      end
    else
      perform_without_throttler
    end
  end
  alias_method :perform_without_throttler, :perform
  alias_method :perform, :perform_with_throttler
  
  # This is added for when there is a dirty exit
  # TODO: testme
  def fail_with_throttler(exception)
    if @throttled
      redis.hmset("throttler:jobs:#{@throttler_uuid}", "ended_at", Time.now.to_i)
    end
    fail_without_throttler(exception)
  end
  alias_method :fail_without_throttler, :fail
  alias_method :fail, :fail_with_throttler
  
end
