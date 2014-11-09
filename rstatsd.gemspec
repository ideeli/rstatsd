$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = 'rstatsd'
  s.version     = '1.0.3'
  s.date        = '2014-11-09'
  s.summary     = "Tool to turn logs into statsd metrics."
  s.description = "rstatsd is a daemon that takes the output of multiple commands and sends
  the output to statsd based on a regular expressions with optional named capture
  groups."
  s.authors     = ["Aaron Brown", "Ulrik Holmen", "Stefan Bergstrom"]
  s.email       = '9minutesnooze@github.com'
  s.files       = `git ls-files -- bin lib config`.split("\n")
  s.homepage    = 'https://github.com/ideeli/rstatsd'
  s.executables = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
  s.default_executable = 'rstatsd'
  s.add_dependency 'statsd-client'
end
