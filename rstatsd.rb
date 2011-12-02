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

class ProcessCtl
  STARTCMD, STOPCMD, STATUSCMD = "start","stop","status" 

  attr_accessor :pidfile, :daemonize

  def initialize
    @pidfile = ""
    @daemonize = false
    @pid = nil
  end

  def start 
    trap(:INT)     { cleanup; stop }
    trap(:SIGTERM) { cleanup; stop }

    size = get_running_pids.size
    if size > 0
      puts "Daemon is already running"
      return 1
    end

#    Daemonize.daemonize if @daemonize
    if @daemonize
      #http://stackoverflow.com/questions/1740308/create-a-daemon-with-double-fork-in-ruby
      raise 'First fork failed' if (pid = fork) == -1
      exit unless pid.nil?

      Process.setsid
      raise 'Second fork failed' if (pid = fork) == -1
      exit unless pid.nil?

      Dir.chdir '/'
      File.umask 0000
      STDIN.reopen '/dev/null'
      STDOUT.reopen '/dev/null', 'a'
      STDERR.reopen STDOUT
    end
    write_pid unless pidfile == ""
    yield
    return 0
  end

  def stop
    # call user code if defined
    begin 
      yield 
    rescue
    end
    get_running_pids.uniq.each do |pid|
      puts "Killing pid #{pid}"
      Process.kill("INT", pid)
      # can't do anything below here.  Process is dead
    end
    return 0
  end

  # returns the exit status (1 if not running, 0 if running)
  def status
    size = get_running_pids.size
    puts "#{File.basename $0} is #{"not " if size < 1}running."
    return (size > 0) ? 0 : 1
  end

protected
  def cleanup
    File.delete(@pidfile) if File.file?(@pidfile) 
#    exit 0
  end

  def write_pid
    @pid = Process.pid
    File.open(@pidfile, "w") do |f|
#      f.write($$)
      f.write(Process.pid)
    end
  end

  def get_running_pids
    return get_child_pids(pid) if @pid
    result = []
    if File.file? @pidfile
      pid = File.read @pidfile
      #result = `ps -p #{pid} -o pid | sed 1d`.to_a.map!{|x| x.to_i}
      @allpids = `ps -ef |sed 1d`.to_a.map { |x| a = x.strip.split(/\s+/); [a[1].to_i,a[2].to_i] }
      puts "getting children of #{pid}"
      result = get_child_pids(pid.to_i) 
      pp result
    end
    return result
  end


  def get_child_pids ( ppid )
    child_pids = @allpids.select { |x| x[1] == ppid }.map { |x| x[0] }
    pids = child_pids
    child_pids.each do |pid|
      pids += get_child_pids(pid)
    end
    pids
  end
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
      trap(:INT) { Process.kill(:INT, pipe.pid) }

      begin
        pipe.each_with_index do |l,i|
          @regexes.each { |r| h = r.get_increments(l, h) }
          # only send to statsd every x lines - this is to avoid UDP floods
          if (i % @every) == 0
            logit("#{i} lines, sending to statsd", Logger::DEBUG) 
            statsd_send(h) 
            h = {}
          end
          # this is for debugging
          sleep(rand/100)
        end
      rescue Exception => e
        logit(e, Logger::ERROR)
      ensure
        Process.kill("INT", pipe.pid) 
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

options = { :cfg_file  => File.dirname(__FILE__)+'/rstatsd.yaml',
            :pidfile   => '/tmp/rstatsd.pid',
            :ctl_cmd   => ARGV[0],
            :daemonize => false }

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
    commands.each do |c| 
      thread = Thread.new { c.execute! }
      threads << thread
    end
    threads.each { |t| t.join } ;
  end
  exit code
end
