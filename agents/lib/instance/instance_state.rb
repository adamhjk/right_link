
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

require 'fileutils'

module RightScale

  # Manages instance state 
  class InstanceState

    # States that will be audited when transitioned to
    RECORDED_STATES   = %w{ booting operational stranded decommissioning }

    # States that cause the system MOTD/banner to indicate that everything is OK
    SUCCESSFUL_STATES = %w{ operational }

    # States that cause the system MOTD/banner to indicate that something is wrong
    FAILED_STATES     = %w{ stranded }

    # Recorded states and additional states local to instance agent
    STATES            = RECORDED_STATES + %w{ decommissioned }

    STATE_DIR         = RightScale::RightLinkConfig[:agent_state_dir]

    # Path to JSON file where current instance state is serialized
    STATE_FILE        = File.join(STATE_DIR, 'state.js')

    # Path to JSON file where past scripts are serialized
    SCRIPTS_FILE      = File.join(STATE_DIR, 'past_scripts.js')

    # Path to JSON file where authorized login users are defined
    LOGIN_POLICY_FILE = File.join(STATE_DIR, 'login_policy.js')

    # Path to boot log
    BOOT_LOG_FILE     = File.join(RightLinkConfig[:platform].filesystem.log_dir, 'install')

    # Path to decommission log
    DECOMMISSION_LOG_FILE = File.join(RightLinkConfig[:platform].filesystem.log_dir, 'decommission')

    # Number of seconds to wait for cloud to shutdown instance
    FORCE_SHUTDOWN_DELAY = 180

    # (String) One of STATES
    def self.value
      @@value
    end

    # (String) Instance agent identity
    def self.identity
      @@identity
    end

    # (Array[(String)]) Scripts that have already executed
    def self.past_scripts
      @@past_scripts
    end

    # (LoginPolicy) The most recently enacted login policy
    def self.login_policy
      @@login_policy
    end

    # Set instance id with given id
    # Load persisted state if any, compare instance ids and force boot if instance ID
    # is different OR if system uptime is less than persisted uptime.
    #
    # === Parameters
    # identity(String):: Instance identity
    #
    # === Return
    # true:: Always return true
    def self.init(identity)
      @@identity = identity
      @@startup_tags = []
      dir = File.dirname(STATE_FILE)
      FileUtils.mkdir_p(dir) unless File.directory?(dir)

      if File.file?(STATE_FILE)
        state = read_json(STATE_FILE)
        RightLinkLog.debug("Initializing instance #{identity} with #{state.inspect}")

        # Initial state reconciliation: use recorded state and uptime to determine how we last stopped.
        # There are four basic scenarios to worry about:
        #  1) first run      -- Agent is starting up for the first time after a fresh install
        #  2) reboot/restart -- Agent already ran; agent ID not changed; reboot detected: transition back to booting
        #  3) bundled boot   -- Agent already ran; agent ID changed: transition back to booting
        #  4) decomm/crash   -- Agent exited anyway; ID not changed; no reboot; keep old state entirely
        if (state['identity'] != identity) || !state['uptime'] || (uptime < state['uptime'].to_f)
          # CASE 2/3 -- identity has changed or negative differential uptime; may be reboot or bundled boot
          RightLinkLog.debug("Reboot/bundle/start detected; transitioning state to booting")
          self.value = 'booting'
        else
          # CASE 4 -- Restart without reboot; don't do anything special.
          @@value = state['value']
          @@startup_tags = state['startup_tags']
          update_logger
        end
      else
        # CASE 1 -- state file does not exist; initial boot, create state file
        RightLinkLog.debug("Initializing instance #{identity} with booting")
        self.value = 'booting'
      end

      if File.file?(SCRIPTS_FILE)
        @@past_scripts = read_json(SCRIPTS_FILE)
      else
        @@past_scripts = []
      end
      RightLinkLog.debug("Past scripts: #{@@past_scripts.inspect}")

      if File.file?(LOGIN_POLICY_FILE)
        @@login_policy = read_json(LOGIN_POLICY_FILE) rescue nil #corrupt file here is not important enough to fail
      else
        @@login_policy = nil
      end
      RightLinkLog.debug("Existing login users: #{@@login_policy.users.length} recorded") if @@login_policy

      true
    end

    # Set instance state
    #
    # === Parameters
    # val(String) One of STATES
    #
    # === Return
    # val(String) new state
    #
    # === Raise
    # RightScale::Exceptions::Argument:: Invalid new value
    def self.value=(val)
      raise RightScale::Exceptions::Argument, "Invalid instance state '#{val}'" unless STATES.include?(val)
      RightLinkLog.info("Transitioning state from #{@@value rescue 'nil'} to #{val}")
      @@value = val
      update_logger
      update_motd

      record_state(val) if RECORDED_STATES.include?(val)
      write_json(STATE_FILE, { 'value' => val, 'identity' => @@identity, 'uptime' => uptime.to_s, 'startup_tags' => @@startup_tags })
      @observers.each { |o| o.call(val) } if @observers
      val
    end

    # Ask core agent to shut ourselves down for soft termination
    # Add a timer to force shutdown if we haven't heard back from the cloud or the request hangs
    #
    # === Parameters
    # user_id(Integer):: ID of user that triggered soft-termination
    # skip_db_update(Boolean):: Whether to requery instance state after call to Ec2 to terminate was made
    #
    # === Return
    # true:: Always return true
    def self.shutdown(user_id, skip_db_update)
      opts = { :agent_identity => @@identity, :state => 'decommissioned', :user_id => user_id, :skip_db_update => skip_db_update }
      RightScale::RequestForwarder.request('/state_recorder/record', opts) do |r|
        res = RightScale::OperationResult.from_results(r)
        RightScale::Platform.controller.shutdown unless res.success?
      end
      EM.add_timer(FORCE_SHUTDOWN_DELAY) { RightScale::Platform.controller.shutdown }
    end

    # Set startup tags
    #
    # === Parameters
    # val(Array):: List of tags
    #
    # === Return
    # val(Array):: List of tags
    def self.startup_tags=(val)
      @@startup_tags = val
    end

    # Tags retrieved on startup
    #
    # === Return
    # tags(Array):: List of tags retrieved on startup
    def self.startup_tags
      @@startup_tags
    end

    # Callback given observer on all state transitions
    #
    # === Block
    # Given block should take one argument which will be the transitioned to state
    #
    # === Return
    # true:: Always return true
    def self.observe(&observer)
      @observers ||= []
      @observers << observer
      true
    end

    # Point logger to log file corresponding to current instance state
    #
    # === Return
    # true:: Always return true
    def self.update_logger
      previous_level = nil
      if @current_logger
        previous_level = @current_logger.level
        RightLinkLog.remove_logger(@current_logger)
      end
      if file = log_file(@@value)
        dir = File.dirname(file)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
        @current_logger = ::Logger.new(File.open(file, 'w'))
        @current_logger.level = previous_level if previous_level
        RightLinkLog.add_logger(@current_logger)
      end
      true
    end

    # Record script execution in scripts file
    #
    # === Parameters
    # nickname(String):: Nickname of RightScript which successfully executed
    #
    # === Return
    # true:: If script was added to past scripts collection
    # false:: If script was already in past scripts collection
    def self.record_script_execution(nickname)
      new_script = !@@past_scripts.include?(nickname)
      if new_script
        @@past_scripts << nickname
        write_json(SCRIPTS_FILE, @@past_scripts)
      end
      new_script
    end

    # Record set of authorized login users
    #
    # === Parameters
    # login_users(Array[(LoginUser)]) set of authorized login users
    #
    # === Return
    # login_users(Array[(LoginUser)]) authorized login users
    #
    def self.login_policy=(login_policy)
      @@login_policy = login_policy.dup
      File.open(LOGIN_POLICY_FILE, 'w') do |f|
        f.write(@@login_policy.to_json)
      end
      login_policy
    end

    protected

    # Log file to be used for given instance state
    #
    # === Parameters
    # state(String):: Instance state, one of STATES
    #
    # === Return
    # log(String):: Log file path
    # nil:: Log file should not be changed
    def self.log_file(state)
      log_file = case state
        when 'booting'         then BOOT_LOG_FILE
        when 'decommissioning' then DECOMMISSION_LOG_FILE
      end
    end

    # Determine uptime of this system using the proc filesystem
    #
    # === Return
    # uptime(Float):: Uptime of this system in seconds, or 0.0 if undetermined 
    def self.uptime()
      return RightScale::RightLinkConfig[:platform].shell.uptime
    end

    # Purely for informational purposes, attempt to update the Unix MOTD file
    # with a pretty banner indicating success or failure. This operation is
    # not critical and does not influence the functionality of the instance,
    # so this method fails silently.
    #
    # === Return
    # nil:: always return nil
    def self.update_motd()
      return unless RightScale::RightLinkConfig.platform.linux?
      
      FileUtils.rm('/etc/motd') rescue nil

      etc = File.join(RightScale::RightLinkConfig[:rs_root_path], 'etc')
      if SUCCESSFUL_STATES.include?(@@value)
        FileUtils.cp(File.join(etc, 'motd-complete'), '/etc/motd') rescue nil
        system('echo "RightScale installation complete. Details can be found in /var/log/messages" | wall') rescue nil
      elsif FAILED_STATES.include?(@@value)
        FileUtils.cp(File.join(etc, 'motd-failed'), '/etc/motd') rescue nil
        system('echo "RightScale installation failed. Please review /var/log/messages" | wall') rescue nil
      else
        FileUtils.cp(File.join(etc, 'motd'), '/etc/motd') rescue nil
      end

      return nil
    end

    private

    # Load JSON from given file
    #
    # === Parameters
    # path(String):: Path to JSON file
    #
    # === Return
    # json(String):: Resulting JSON string
    #
    # === Raise
    # Errno::ENOENT:: Invalid path
    # JSON Exception:: Invalid JSON content
    def self.read_json(path)
      JSON.load(File.read(path))
    end
    
    # Serialize object to JSON and write result to file, override existing file if any.
    # Note: Do not serialize object if it's a string, allows passing raw JSON.
    #
    # === Parameters
    # path(String):: Path to file being written
    # contents(Object|String):: Object to be serialized into JSON or JSON string
    #
    # === Return
    # true:: Always return true
    def self.write_json(path, contents)
      contents = contents.to_json unless contents.is_a?(String)
      File.open(path, 'w') { |f| f.write(contents) }
      true
    end

    # Record state transition with core agent
    #
    # === Parameters
    # new_state(String):: One of RECORDED_STATES
    #
    # === Return
    # true:: Always return true
    def self.record_state(new_state)
      options = { :agent_identity => @@identity, :state => new_state }
      RightScale::RequestForwarder.request('/state_recorder/record', options) do |r|
        res = RightScale::OperationResult.from_results(r)
        RightLinkLog.warn("Failed to record state: #{res.content}") unless res.success?
      end
      true
    end

  end

end
