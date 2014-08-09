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
      @rate_limits[queue.to_s]
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
  
  def perform_with_throttler
    if Resque.queue_rate_limited?(self.queue)
      uuid = SecureRandom.uuid
      begin
        # TODO this needs to be wrapped in a transcation
        redis.hmset("throttler:jobs:#{uuid}", "started_at", Time.now.to_i)
        redis.sadd("throttler:#{queue}_uuids", uuid)
        perform_without_throttler
      ensure
        redis.hmset("throttler:jobs:#{uuid}", "ended_at", Time.now.to_i)
      end
    else
      perform_without_throttler
    end
  end
  alias_method :perform_without_throttler, :perform
  alias_method :perform, :perform_with_throttler
  
end
