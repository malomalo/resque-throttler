require 'resque'
require 'securerandom'

module Resque::Plugins
  module Throttler
    extend self

    attr_writer :perform_inline_rate_limit_gc

    def self.extended(other)
      other.instance_variable_set(:@rate_limits, {})
    end

    def perform_inline_rate_limit_gc
      if defined?(@perform_inline_rate_limit_gc)
        @perform_inline_rate_limit_gc
      else
        true
      end
    end

    def pop(queue)
      if queue_at_or_over_rate_limit?(queue)
        gc_rate_limit_data_for_queue(queue) if perform_inline_rate_limit_gc
        nil
      else
        super
      end
    end

    def rate_limit(queue, options={})
      if [:at, :per].any? { |key| !options.keys.include? key }
        raise ArgumentError.new("Mising either :at or :per in options")
      elsif !(options.keys - [:at, :per, :job_timeout]).empty?
        raise ArgumentError.new("Unknown rate limit keys #{(options.keys - [:at, :per, :job_timeout]).join(', ')}")
      end

      @rate_limits[queue.to_s] = options
    end

    def rate_limit_for(queue)
      @rate_limits[queue.to_s]
    end

    def queue_rate_limited?(queue)
      !!@rate_limits[queue.to_s]
    end

    def rate_limited_queues
      @rate_limits.keys
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
        job_hash = redis.hgetall("throttler:jobs:#{uuid}")

        job_started_at = job_hash['started_at']
        job_ended_at = job_hash['ended_at']

        # Happy Path
        gc_job = job_ended_at && Time.at(job_ended_at.to_i) < Time.now - limit[:per]

        if job_hash.empty?
          warn "[resque-throttler] job in #{queue} queue detected with empty rate limit hash"
          gc_job = true
        end

        if limit[:job_timeout] && job_started_at && Time.at(job_started_at.to_i) < Time.now - limit[:job_timeout]
          warn "[resque-throttler] job in #{queue} queue exceeded job timeout"
          gc_job = true
        end

        if gc_job
          redis.multi do
            redis.srem(queue_key, uuid)
            redis.del("throttler:jobs:#{uuid}")
          end
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
