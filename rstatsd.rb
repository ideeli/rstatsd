#!/usr/bin/env ruby

# 
# rstatsd.rb - a daemon that follows the output of a command, matches regexes, and logs the data to statsd/graphite
#

require 'pp'
require 'yaml'
require 'rubygems'
require 'statsd'

if RUBY_VERSION =~ /1\.8/
  require 'oniguruma'

  module Oniguruma
    class ::MatchData
      def names
        # this is weak, but .names is not implemented in the Oniguruma gem
        return [] unless @named_captures
        @named_captures.keys.map { |x| x.to_s }
      end
    end
  end
end

# return the oniguruma version of the regex is using ruby 1.8.x
def regex ( r )
  RUBY_VERSION =~ /1\.8/ ? Oniguruma::ORegexp.new(r) : /#{r}/
end

def get_full_metric_name ( a_values )
  a_values.join(".")
end

options = { :cfg_file => File.dirname(__FILE__)+'/rstatsd.yaml',
}

cfg = YAML.load_file(options[:cfg_file])

cmd = cfg[:cmds][0]


Statsd.host = cfg[:statsd][:host]
Statsd.port = cfg[:statsd][:port]

h = {}
IO.popen(cmd[:cmd]).each do |l|
  cmd[:regexes].each do |r|
    rex = regex r[:regex]
    match = rex.match(l)
    next unless match

    if match.names.empty?
      # no capture group, just log it
      r[:metrics].each do |metric|
      end
    else
      # has capture groups, use the value of the capture group as the metric name
      match.names.each do |name|
        r[:metrics].each do |metric|
          if r[:statsd]
            fullmetric = get_full_metric_name( [ cfg[:metric_prefix], metric, name, match[name.to_sym] ] )
            Statsd.increment(fullmetric)
          end
        end
        # this is for debugging
        sleep(rand/100)
      end
    end
  end
end
