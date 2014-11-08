module RStatsd
  ENV['TZ'] = ":/etc/localtime"

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
    attr_accessor :command
    def initialize ( h = {}, &block )
      @command  = nil
      @logger   = h[:logger]
      @every    = h[:every] || 1
      @interval = h[:interval] || nil
      @prefix   = h[:prefix]
      @regexes  = []

      yield self
    end

    def add_regex ( regex )
      regex.logger = @logger
      @regexes << regex
    end

    def execute!
      trap(:INT)  { logit("Caught SIGINT.  Exiting");  Process.kill(:INT,  pipe.pid) }
      trap(:TERM) { logit("Caught SIGTERM.  Exiting"); Process.kill(:TERM, pipe.pid) }
      
      timers, counters, gauges = {}, {}, {}
      
      logit("Starting thread for command #{@command}; interval #{@interval}, every #{@every}")
      pipe = IO.popen(@command)
      begin
        if @interval
          next_update = Time.now.to_f + @interval
        end

        pipe.each_with_index do |l,i|
          @regexes.each do |r| 
            if r.statsd_type == RegExData::Timer
              timers = r.get_increments(l, timers)
            elsif r.statsd_type == RegExData::Gauge
              gauges = r.get_increments(l, gauges)
            else
              counters = r.get_increments(l, counters)
            end
          end
          
          if @interval
              do_update = Time.now.to_f >= next_update
          else
              do_update = (i % @every) == 0
          end

          if do_update
            logit("#{@command}: #{i} lines, sending to statsd", Logger::DEBUG)
            statsd_send(counters) 
            statsd_send(gauges, 'gauge') 
            statsd_send(divide_hash(timers, @every), 'timer')
            timers, counters, gauges = {}, {}, {}
            if @interval
              next_update = Time.now.to_f + @interval
            end
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

    # divide all values in Hash h by divisor
    def divide_hash ( h, divisor )
      Hash[h.map { |k,v| [k, v = v.to_f/divisor.to_f] }]
    end

    def statsd_send ( h, statsd_type = nil )
      # prefix keys unless they are prefixed by '/'
      h.prefix_keys(@prefix) { |k,v| k[0,1] != '/' }.each do |k,v| 
        k = k.gsub(/^\//,'')  # strip leading '/'
        if statsd_type == 'timer'
          Statsd.timing(k,v)
          logit("Set timer value #{k} to #{v}",Logger::DEBUG) 
        elsif statsd_type == 'gauge'
          Statsd.gauge(k,v)
          logit("Set gauge value #{k} to #{v}",Logger::DEBUG) 
        else
          Statsd.update_counter(k,v)
          logit("Incremented #{k} by #{v}",Logger::DEBUG) 
        end
      end
    end
  end

  class RegExData
    include Helpers

    attr_writer :logger
    attr_reader :regex, :statsd_type

    Counter, Timer, Gauge = 1, 2, 3

    def initialize ( h )
      @regex       = which_regex h[:regex]
      @metrics     = h[:metrics] || []
      @statsd_type = case h[:statsd_type]
                     when 'timer' then Timer 
                     when 'gauge' then Gauge
                     else Counter 
                     end
      @statsd      = h[:statsd] || true
      @carbon      = !!h[:carbon] 
      @logger      = h[:logger]
      @use_value   = !!h[:use_value] 

      # timers implicitly use the value
      if @statsd_type == Timer
        @use_value = true
      end
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
          if @statsd_type == Timer
            h[metric_name] += @matches[name.to_sym].to_f
          elsif @statsd_type == Gauge
            h[metric_name] = @matches[name.to_sym].to_f
          else
            h[metric_name] += @matches[name.to_sym].to_i
          end
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

