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
      trap(:INT)  { logit("Caught SIGINT.  Exiting");  Process.kill(:INT,  pipe.pid) }
      trap(:TERM) { logit("Caught SIGTERM.  Exiting"); Process.kill(:TERM, pipe.pid) }
      h = {}
      
      logit("Starting thread for command #{@command}")
      pipe = IO.popen(@command)
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
#sleep(rand/100)
        end
      rescue Exception => e
        logit(e, Logger::ERROR)
      ensure
        Process.kill(:TERM, pipe.pid) 
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
      @regex     = which_regex h[:regex]
      @metrics   = h[:metrics] || []
      @statsd    = h[:statsd] || true
      @carbon    = !!h[:carbon] 
      @logger    = h[:logger]
      @use_value = !!h[:use_value] 
    end

    def get_increments ( line, h )
      h ||= {}
      @matches = @regex.match(line)
      return h unless @matches
      if has_captures?
        @matches.names.each do |name|
          h = build_and_increment(h, name )
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
        if @use_value && name
          # the value of the named capture will be used as the increment
          metric_name = prefix_metric_name( [ metric_name, name ] ) 
          h[metric_name] ||= 0
          h[metric_name] += @matches[name.to_sym].to_i
        else
          # the value of the named capture will be used as a leaf node in the mtric name
          metric_name = prefix_metric_name( [ metric_name, name, @matches[name.to_sym] ] ) if name
          h[metric_name] ||= 0
          h[metric_name] += 1
        end
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

