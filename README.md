rstatsd
=======

rstatsd is a daemon that takes the output of multiple commands and sends the output to [statsd](/etsy/statsd) based on a regular expressions with optional named capture groups.


installation
------------
It's not a gem yet.  In the meantime, you can install rstatsd like this:

    gem install statsd-client
    git clone https://9minutesnooze@github.com/9minutesnooze/rstatsd.git

If you are running Ruby 1.8, you will also need to install the [oniguruma](http://oniguruma.rubyforge.org/) gem and [development headers](http://www.geocities.jp/kosako3/oniguruma/).

Ubuntu 10.04

    apt-get install libonig-dev libonig2
    gem install oniguruma

OSX 

    sudo port install oniguruma4
    gem install oniguruma

If you know how to easily install oniguruma on other platforms, let me know.

You will also need `ps` in your `$PATH`.  

configuration
-------------
All configuration is done with a [yaml file](rstatsd/rstatsd-example.yaml).  A basic yaml file looks like this:

    ---
    :logfile: "/var/log/rstatsd.log
    :metric_prefix: "com.example.www."
    - :cmd: "tail -F /var/log/nginx/blog_access.log"
      :regexes: 
      - :regex: '^.*$'
        :metrics: 
        - "blog.requests"
      - :regex: '(?<http_method>[A-Z]+)\s.*?\sHTTP/1\.1"\s(?<http_code>\d+)\s'
        :metrics: 
        - "blog"
    :statsd: 
      :host: "graphite.example.com"
      :port: 8125

This will make rstatsd tail blog_access.log and check it against two regular expressions.  The first regular expression `^.*$` will match everything and increment the metric `com.example.www.blog` (the com.example.www piece comes from the `:metric_prefix`).  This will log all requests to statsd.  

The second regex `(?<http_method>[A-Z]+)\s.*?\sHTTP/1\.1"\s(?<http_code>\d+)\s` uses named capture groups and is a little bit more complicated.  It will use the name of the capture (http_method, http_code) as a parent metric name, and the value of the capture as the leaf of the metric name.  In this example, that means that you will get statistics on the following metrics:

    com.example.www.blog.http_method.GET
    com.example.www.blog.http_method.POST
    com.example.www.blog.http_method.HEAD
    ...

and

    com.example.www.blog.http_code.200
    com.example.www.blog.http_code.301
    com.example.www.blog.http_code.302
    com.example.www.blog.http_code.404
    com.example.www.blog.http_code.500
    ...

Want to watch more than one commend?  Just do it.  rstatsd is multithreaded, so you can specify as many `:cmd` sections and as many regular expressions as you find interesting.

command line options
--------------------

    $ ./rstatsd.rb --help
    Usage: ./rstatsd.rb [options]
        -d, --[no-]daemonize             Daemonize (default false)
        -c, --config FILE                Configuration file (default ./rstatsd.yaml)
        -p, --pidfile FILE               PID file (default /tmp/rstatsd.pid)
        -k, --command COMMAND            Command (start|stop|status)
        -h, --help                       Show this message


Start it, as a daemon with a config file in /etc
    
    $ ./rstatsd.rb -c /etc/rstatsd.yaml -d -k start

Stop it

    $ ./rstatsd.rb -k stop
    I'm done
    Killing pid 6540
    Killing pid 6542
    Killing pid 6544
    Killing pid 6546
    Killing pid 6548
    Killing pid 6550
    Killing pid 6552
    Killing pid 6538


Is it running? 

    $ ./rstatsd.rb -k status
    rstatsd.rb is running.
    $ echo $?
    1 
    $ ./rstatsd.rb -k stop
    ...
    $ ./rstatsd.rb -k status
    rstatsd.rb is not running.
    $ echo $?
    1 

limiting UDP calls
------------------
I originally wrote rstatsd to pull stats out of nginx logs that occur upwards of 60k times a minute.  Even with UDP, that's kind of a lot of network traffic.  To reduce the volume of UDP requests, you can add `:every: n` to a `:cmd` to only submit to statsd after every n lines.

For example,

    - :cmd: "tail -F /var/log/nginx/blog_access.log"
      :every: 100
      :regexes:
      - :regex: '^.*$'
        :metrics:
        - "blog.requests"


This will only send data to statsd every 100 lines, thus reducing UDP traffic by 100x.  Never make the `:every` value less than what you expect your minimum traffic will be per aggregation interval as defined in statsd and carbon.

other cool stuff
----------------

You can specify multiple `:metrics` per `:regex` so you can have an aggregate (multiple host) stat and also one specific to this host.  Or for some other reason.  But you can do it.



stuff I want to do, but haven't yet 
-----------------------------------
* When metrics are prefixed by a `/`, ignore the `:metric_prefix`
* be able to make `:metric_prefix` take a Proc
* write some tests
* document the code
* optional logging to carbon/graphite for self-contained metrics
