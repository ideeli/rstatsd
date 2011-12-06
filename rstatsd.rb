#!/usr/bin/env ruby

# 
# rstatsd.rb - a daemon that follows the output of a command, matches regexes, and logs the data to statsd/graphite
#

require 'pp'
require 'yaml'
require 'logger'
require 'optparse'
require 'rubygems'
require 'statsd'
require 'lib/rstatsd'

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


options = { :cfg_file  => File.dirname(__FILE__)+'/rstatsd.yaml',
            :pidfile   => '/tmp/rstatsd.pid',
            :ctl_cmd   => "start",
            :daemonize => false }


OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"
  opts.on("-d", "--[no-]daemonize", "Daemonize (default #{options[:daemonize]})") do |v|
    options[:daemonize] = v
  end
  opts.on("-c", "--config FILE", String, "Configuration file (default #{options[:cfg_file]})") do |v|
    options[:cfg_file] = v
  end
  opts.on("-p", "--pidfile FILE", String, "PID file (default #{options[:pidfile]})") do |v|
    options[:pidfile] = v
  end
  opts.on("-k", "--command COMMAND", [:start,:stop,:status], "Command (start|stop|status)") do |v|
    options[:ctl_cmd] = v
  end
  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end.parse!

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

pc = ProcessCtl.new
pc.daemonize = options[:daemonize]
pc.pidfile   = options[:pidfile]

case options[:ctl_cmd]
when ProcessCtl::STOPCMD 
  pc.stop { puts "I'm done" }
when ProcessCtl::STATUSCMD 
  exit pc.status
else
  code = pc.start do
    commands.each { |c| threads << Thread.new { c.execute! } }
    threads.each  { |t| t.join }
  end
  exit code
end
