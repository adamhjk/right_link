# === Synopsis:
#   RightScale Agent Deployer (rad) - (c) 2009 RightScale
#
#   rad is a command line tool that allows building the configuration file for
#   a given agent.
#   The configuration files will be generated in:
#     right_net/generated/<name of agent>/config.yml
#
# === Examples:
#   Build configuration for AGENT with default options:
#     rad AGENT
#
#   Build configuration for AGENT so it uses given AMQP settings:
#     rad AGENT --user USER --pass PASSWORD --vhost VHOST --port PORT --host HOST
#     rad AGENT -u USER -p PASSWORD -v VHOST -P PORT -h HOST
#
# === Usage:
#    rad AGENT [options]
#
#    options:
#      --identity, -i ID        Use base id ID to build agent's identity
#      --shared-queue, -q QUEUE Use QUEUE as input for agent in addition to identity queue
#      --token, -t TOKEN        Use token TOKEN to build agent's identity
#      --prefix, -r PREFIX:     Prefix nanite agent identity with PREFIX
#      --user, -u USER:         Set agent AMQP username
#      --password, -p PASS:     Set agent AMQP password
#      --vhost, -v VHOST:       Set agent AMQP virtual host
#      --port, -P PORT:         Set AMQP server port
#      --host, -h HOST:         Set AMQP server host
#      --alias ALIAS:           Use alias name for identity and base config
#      --actors-dir, -a DIR:    Set directory containing actor classes
#      --pid-dir, -z DIR:       Set directory containing pid file
#      --monit, -w:             Generate monit configuration file
#      --options, -o KEY=VAL:   Pass-through options
#      --http-proxy, -P PROXY:  Use a proxy for all agent-originated HTTP traffic
#      --no-http-proxy          Comma-separated list of proxy exceptions
#      --test:                  Build test deployment using default test settings
#      --quiet, -Q              Do not produce output
#      --help:                  Display help
#      --version:               Display version information

require 'optparse'
require 'rdoc/ri/ri_paths' # For backwards compat with ruby 1.8.5
require 'rdoc/usage'
require 'yaml'
require 'ftools'
require 'fileutils'
require File.join(File.dirname(__FILE__), 'rdoc_patch')
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'config', 'right_link_config'))
require File.join(File.dirname(__FILE__), 'agent_utils')
require File.join(File.dirname(__FILE__), 'common_parser')
require File.normalize_path(File.join(File.dirname(__FILE__), '..', '..', 'common', 'lib', 'common'))

module RightScale

  class AgentDeployer

    include Utils
    include CommonParser

    VERSION = [0, 2]

    # Helper
    def self.run
      d = AgentDeployer.new
      d.generate_config(d.parse_args)
    end

    # Do deployment with given options
    def generate_config(options)
      init_rb_path = nil
      actors = nil
      actors_path = nil
      actors_path = options[:actors_dir] || actors_dir
      cfg = agent_config(options[:agent], options[:alias])
      fail("Cannot read configuration for agent #{options[:agent]}") unless cfg
      actors = cfg.delete(:actors)
      fail('Agent configuration does not define actors') unless actors && actors.respond_to?(:each)
      actors.each do |actor|
        actor_file = File.join(actors_path, "#{actor}.rb")
        fail("Cannot find actor file '#{actor_file}'") unless File.exist?(actor_file)
      end
      options[:actors_path] = actors_path
      options[:actors] = actors
      options[:init_rb_path] = File.join(agent_dir(options[:alias] || options[:agent]), (options[:alias] || options[:agent]) + ".rb")
      options[:pid_prefix] = 'nanite'
      write_config(options)
    end

    # Generate configuration files
    def write_config(options)
      cfg = {}
      cfg[:identity]     = options[:identity] if options[:identity]
      cfg[:shared_queue] = options[:shared_queue] if options[:shared_queue]
      cfg[:pid_dir]      = options[:pid_dir] || '/var/run'
      cfg[:user]         = options[:user] if options[:user]
      cfg[:pass]         = options[:pass] if options[:pass]
      cfg[:vhost]        = options[:vhost] if options[:vhost]
      cfg[:port]         = options[:port] if options[:port]
      cfg[:host]         = options[:host] if options[:host]
      cfg[:initrb]       = options[:init_rb_path] if options[:init_rb_path]
      cfg[:actors]       = options[:actors] if options[:actors]
      cfg[:actors_dir]   = options[:actors_path] if options[:actors_path]
      cfg[:format]       = 'secure'
      cfg[:http_proxy]   = options[:http_proxy] if options[:http_proxy]
      cfg[:no_http_proxy]= options[:no_http_proxy] if options[:no_http_proxy]
      options[:options].each { |k, v| cfg[k] = v } if options[:options]

      agent_dir = gen_agent_dir(options[:agent])
      File.makedirs(agent_dir) unless File.exist?(agent_dir)
      conf_file = config_file(options[:agent])
      File.delete(conf_file) if File.exist?(conf_file)
      File.open(conf_file, 'w') { |fd| fd.puts "# Created at #{Time.new}" }
      File.open(conf_file, 'a') do |fd|
        fd.write(YAML.dump(cfg))
      end
      unless options[:quiet]
        puts "Generated configuration file for agent #{options[:agent]}:"
        puts "  - config: #{conf_file}"
      end
        
      if options[:monit]
        config_file = setup_monit(options)
        puts "  - monit config: #{config_file}" unless options[:quiet]
      end
    end

    # Create options hash from command line arguments
    def parse_args
      options = {}
      options[:agent] = ARGV[0]
      options[:options] = {}
      options[:quiet] = false
      fail('No agent specified on the command line.', print_usage=true) if options[:agent].nil?

      opts = OptionParser.new do |opts|
        parse_common(opts, options)
        parse_other_args(opts, options)

        opts.on('-a', '--actors-dir DIR') do |d|
          options[:actors_dir] = d
        end

        opts.on('-q', '--shared-queue QUEUE') do |q|
          options[:shared_queue] = q
        end

        opts.on('-z', '--pid-dir DIR') do |d|
          options[:pid_dir] = d
        end

        opts.on('-w', '--monit') do
          options[:monit] = true
        end

        opts.on('-P', '--http-proxy PROXY') do |proxy|
          options[:http_proxy] = proxy
        end

        opts.on('--no-http-proxy NOPROXY') do |no_proxy|
          options[:no_http_proxy] = no_proxy
        end

        opts.on('-o', '--options OPT') do |e|
          fail("Invalid option definition '#{e}' (use '=' to separate name and value)") unless e.include?('=')
          key, val = e.split(/=/)
          options[:options][key.gsub('-', '_').to_sym] = val
        end

        opts.on('-Q', '--quiet') do
          options[:quiet] = true
        end

        opts.on_tail('--help') do
          RDoc::usage_from_file(__FILE__)
          exit
        end
      end
      begin
        opts.parse!(ARGV)
      rescue Exception => e
        puts e.message + "\nUse rad --help for additional information"
      end
      resolve_identity(options)
      options
    end

    # Parse any other arguments used by agent
    def parse_other_args(opts, options)
    end

protected

    # Print error on console and exit abnormally
    def fail(msg=nil, print_usage=false)
      puts "** #{msg}" if msg
      RDoc::usage_from_file(__FILE__) if print_usage      
      exit(1)
    end

    # Create monit configuration file
    def setup_monit(options)
      agent = options[:agent]
      pid_file = PidFile.new("#{options[:pid_prefix]}-#{options[:identity]}", :pid_dir => options[:pid_dir] || '/var/run')
      monit_config_file = if File.exists?('/opt/rightscale/etc/monit.d')
        File.join('/opt/rightscale/etc/monit.d', "#{agent}-#{options[:identity]}.conf")
      else
        File.join(gen_agent_dir(agent), "#{agent}-#{options[:identity]}-monit.conf")
      end
      File.open(monit_config_file, 'w') do |f|
        f.puts <<-EOF
check process #{agent}
  with pidfile \"#{pid_file}\"
  start program \"/usr/bin/rnac --start #{agent}\"
  stop program \"/usr/bin/rnac --stop #{agent}\"
  mode manual
        EOF
      end
      # monit requires strict perms on this file
      File.chmod 0600, monit_config_file
      monit_config_file
    end

    def config_file(agent)
      File.join(gen_agent_dir(agent), 'config.yml')
    end
    
    def agent_config(agent, alias_name=nil)
      cfg_file = File.join(agent_dir(alias_name || agent), "#{alias_name || agent}.yml")
      return nil unless File.exist?(cfg_file)
      symbolize(YAML.load(IO.read(cfg_file))) rescue nil
    end

    # Version information
    def version
      "rad #{VERSION.join('.')} - RightScale Agent Deployer (c) 2009 RightScale"
    end

  end
end

#
# Copyright (c) 2009 RightScale Inc
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
