Resque Throttler
================

Resque Throttler allows you to throttle the rate at which jobs are performed
on a specific queue.


Installation
============

```ruby
require 'resque/throttler'
```

Or in a Gemfile:

```ruby
require 'resque-throttler', :require => 'resque/throttler'
```

Usage
=====

```ruby
require 'resque'
require 'resque/throttler'

# Rate limit at 10 jobs from `my_queue` per minute
Resque.rate_limit(:my_queue, :at => 10, :per => 60)
```