namespace :resque do
  desc 'Performs garbage collection on all rate limited queues'
  task rate_limit_gc: [ :preload, :setup ] do
    loop do
      Resque.rate_limited_queues.each do |queue|
        Resque.gc_rate_limit_data_for_queue(queue)
      end

      sleep (ENV['RESQUE_RATE_LIMIT_GC_SLEEP'] || 0.25).to_f
    end
  end
end
