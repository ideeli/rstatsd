Gem::Specification.new do |s|
  s.name        = 'rstatsd'
  s.version     = '1.0.0'
  s.date        = '2014-09-27'
  s.summary     = "Tool to turn logs into statsd metrics."
  s.description = "rstatsd is a daemon that takes the output of multiple commands and sends
  the output to statsd based on a regular expressions with optional named capture
  groups."
  s.authors     = ["Aaron Brown"]
  s.email       = '9minutesnooze@github.com'
  s.files       = ["lib/oniguruma.rb", "lib/rstatsd/rstatsd.rb", "lib/rstatsd/hash.rb", "lib/rstatsd/processctl.rb", "rstatsd.rb"]
  s.homepage    = 'https://github.com/ideeli/rstatsd'
  s.license     = 'MIT'
end
