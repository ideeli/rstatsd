class ProcessCtl
  STARTCMD, STOPCMD, STATUSCMD = :start, :stop, :status

  attr_accessor :pidfile, :daemonize

  def initialize
    @pidfile = ""
    @daemonize = false
    @pid = nil
  end

  def start 
    trap(:INT)  { stop ; cleanup}
    trap(:TERM) { stop ; cleanup}

    pids = get_running_pids
    if pids.size > 0
      puts "Daemon is already running (pids #{pids.join(',')})"

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
    trap(:INT)  { stop }
    trap(:TERM) { stop }
    yield
    return 0
  end

  def stop
    # call user code if defined
    begin 
      yield 
    rescue Exception => e
    ensure
      get_running_pids.uniq.each do |pid|
        puts "Killing pid #{pid}"
        cleanup if pid == @pid.to_i
        Process.kill("TERM", pid)
        # can't do anything below here.  Process is dead
      end
      return 0
    end
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

  def pid_is_running ( pid )
    !@allpids.select { |x| x[0] == pid }.empty?
  end

  def get_running_pids
    return get_child_pids(@pid) if @pid
    result = []
    if File.file? @pidfile
      pid = File.read(@pidfile)
      pid = pid.to_i
      get_allpids
      if pid_is_running(pid)
        result = get_child_pids(pid.to_i)
        result << pid.to_i
      end
    end
    return result
  end

  def get_allpids
    @allpids = `ps -ef |sed 1d`.to_a.map { |x| a = x.strip.split(/\s+/); [a[1].to_i,a[2].to_i] }
  end

  # thar be recursion ahead, matey
  # get a list of all child pids
  def get_child_pids ( ppid )
    child_pids = @allpids.select { |x| x[1] == ppid }.map { |x| x[0] }
    pids = child_pids
    child_pids.each do |pid|
      pids += get_child_pids(pid)
    end
    pids
  end
end

