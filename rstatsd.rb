#!/usr/bin/env ruby

# 
# rstatsd.rb - a daemon that follows the output of a command, matches regexes, and logs the data to statsd/graphite
#

require 'pp'
require 'yaml'
require 'rubygems'
require 'statsd'
require 'logger'

# this program needs named capture groups, which are not available
# in Ruby 1.8.x
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

def setup_logger ( logfile, loglevel = "INFO"  )
  logger = Logger.new( logfile, 'daily')
  begin
    logger.level = eval("Logger::#{loglevel}")
  rescue Exception => e
    logger.level = Logger::INFO
  end
  logger
end


class Hash
  def prefix_keys ( prefix )
    Hash[self.map { |k,v| [ "#{prefix}#{k}", v] }]
  end
end

module RStatsd
  module Helpers
    def prefix_metric_name ( pieces )
      pieces.join(".")
    end

    def logit ( msg, level = Logger::INFO )
      @logger.add(level) { "[#{Thread.current.object_id}] #{msg}" }
    end
  end

  class Command
    include Helpers
    attr_accessor :command, :every
    def initialize ( h = {}, &block )
      @command = nil
      @logger  = h[:logger]
      @every   = h[:every] || 1
      @prefix  = h[:prefix]
      @regexes = []   
      yield self
    end

    def add_regex ( regex )
      regex.logger = @logger
      @regexes << regex
    end

    def execute!
      h = {}
      
      logit("Starting thread for command #{@command}")
      pipe = IO.popen(@command)

      pipe.each_with_index do |l,i|
        trap("INT") { Process.kill("INT", pipe.pid) }
        begin
          @regexes.each { |r| h = r.get_increments(l, h) }
          # only send to statsd every x lines - this is to avoid UDP floods
          if (i % @every) == 0
            logit("#{i} lines, sending to statsd", Logger::DEBUG) 
            statsd_send(h) 
            h = {}
          end
        rescue Exception => e
          logit(e, Logger::ERROR)
          Process.kill("INT", pipe.pid) 
        end

        # this is for debugging
        sleep(rand/100)
      end
    end

    def statsd_send ( h )
      h.prefix_keys(@prefix).each do |k,v| 
        Statsd.update_counter(k,v)
        logit("Incremented #{k} by #{v}",Logger::DEBUG) 
      end
    end
  end

  class RegExData
    include Helpers

    attr_writer :logger

    def initialize ( h )
      @regex   = which_regex h[:regex]
      @metrics = h[:metrics] || []
      @statsd  = h[:statsd] || true
      @carbon  = !!h[:carbon] 
      @logger  = h[:logger]
    end

    def get_increments ( line, h )
      h ||= {}
      @matches = @regex.match(line)
      return h unless @matches
      if has_captures?
        @matches.names.each do |name|
          h = build_and_increment(h, name)
        end
      else
        h = build_and_increment(h)
      end
      h
    end

  private
    def build_and_increment ( h, name = nil )
      h ||= {}
      @metrics.each do |metric|
        metric_name = metric
        metric_name = prefix_metric_name( [ metric_name, name, @matches[name.to_sym] ] ) if name
        h[metric_name] ||= 0
        h[metric_name] += 1
      end
      h
    end
    
    def has_captures? 
      !@matches.names.empty?
    end

    # return the oniguruma version of the regex is using ruby 1.8.x
    def which_regex ( regex )
      RUBY_VERSION =~ /1\.8/ ? Oniguruma::ORegexp.new(regex) : /#{regex}/
    end
  end
end

options = { :cfg_file => File.dirname(__FILE__)+'/rstatsd.yaml' }

cfg = YAML.load_file(options[:cfg_file])

Statsd.host = cfg[:statsd][:host]
Statsd.port = cfg[:statsd][:port]

commands = []
threads  = []
logger   = setup_logger(cfg[:logfile] || STDOUT, cfg[:loglevel] || "INFO")

cfg[:cmds].each do |cmd|
  params = { :every  => cmd[:every], 
             :logger => logger, 
             :prefix => cfg[:metric_prefix] }

  commands << RStatsd::Command.new(params) do |c|
    c.command = cmd[:cmd]
    cmd[:regexes].each { |regex| c.add_regex RStatsd::RegExData.new(regex)  }
  end
end

commands.each { |c| threads << Thread.new { c.execute! }; sleep 1 }
threads.each { |t| t.join }
