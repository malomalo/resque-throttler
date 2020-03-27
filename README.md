Resque Throttler [![Circle CI](https://circleci.com/gh/malomalo/resque-throttler.svg?style=svg)](https://circleci.com/gh/malomalo/resque-throttler)
================

Resque Throttler allows you to throttle the rate at which jobs are performed
on a specific queue.

If the queue is above the rate limit then the workers will ignore the queue
until the queue is below the rate limit.

Installation
------------

```ruby
require 'resque/throttler'
```

Or in a Gemfile:

```ruby
gem 'resque-throttler', require: 'resque/throttler'
```

Usage
-----

```ruby
require 'resque'
require 'resque/throttler'

# Rate limit at 10 jobs from `my_queue` per minute, ignores jobs that have taken more than an hour
Resque.rate_limit(:my_queue, at: 10, per: 60, max_duration: 3600)
```

Centralized Garbage Collection
-----

With many resque proceses and large rate limits the amount of work maintaining the rate limit data
in Redis can grow outside what should be performed by resque processes. In this case, a centralized
rake task should be used to prevent resque worker slowdown and Redis CPU pressure.

In your Rakefile, add:
```
require 'resque/throttler/tasks'
```

And execute the long-running rake task, similar to a resque worker:
```bash
bundle exec rake resque:rate_limit_gc
```

Similar Resque Plugins
----------------------

* [resque-queue-lock](https://github.com/mashion/resque-queue-lock)

  Only allows one job to be performed at once from a `queue`. With Resque
  Throttler you can achieve the same functionarliy with the following rate limit:

  ```ruby
  Resque.rate_limit(:my_queue, :at => 1, :per => 0)
  ```

* [resque-throttle](https://github.com/scotttam/resque-throttle)

  Works on a `class` rather than a `queue` and will throw and error when you
  try to enqueue at job when the `class` is at or above it's rate limit.

* [resque-waiting-room](https://github.com/julienXX/resque-waiting-room)

  Looks like it also works on a `class` and throws the jobs into a
  `"waiting_room"` queue that then gets processed.
