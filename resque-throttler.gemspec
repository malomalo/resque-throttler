Gem::Specification.new do |s|
  s.name        = "resque-throttler"
  s.version     = '0.1.5'
  s.licenses    = ['MIT']
  s.authors     = ["Jon Bracy"]
  s.email       = ["jonbracy@gmail.com"]
  s.homepage    = "https://github.com/malomalo/resque-throttler"
  s.summary     = %q{Rate limit Resque Jobs}
  s.description = %q{Rate limit how many times a job can be run from a queue}

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.extensions    = []
  s.require_paths = ["lib"]
  #s.extra_rdoc_files = ["LICENSE", "README.md"]
  
  # Developoment 
  s.add_development_dependency 'rake'
  #s.add_development_dependency 'rdoc'
  #s.add_development_dependency 'sdoc'
  s.add_development_dependency 'bundler'
  s.add_development_dependency 'activesupport'
  s.add_development_dependency 'minitest'
  s.add_development_dependency 'minitest-reporters'
  s.add_development_dependency 'mocha'
  #s.add_development_dependency 'sdoc-templates-42floors'

  # Runtime
  s.add_runtime_dependency 'resque', '>= 1.25'
end