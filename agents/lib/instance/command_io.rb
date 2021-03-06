# Copyright (c) 2009 RightScale, Inc, All Rights Reserved Worldwide.
#
# THIS PROGRAM IS CONFIDENTIAL AND PROPRIETARY TO RIGHTSCALE
# AND CONSTITUTES A VALUABLE TRADE SECRET.  Any unauthorized use,
# reproduction, modification, or disclosure of this program is
# strictly prohibited.  Any use of this program by an authorized
# licensee is strictly subject to the terms and conditions,
# including confidentiality obligations, set forth in the applicable
# License Agreement between RightScale.com, Inc. and
# the licensee.

require 'singleton'

module RightScale

  # EventMachine connection
  # Define event loop callbacks handler
  module InputHandler

    # Keep block used to handle incoming data
    #
    # === Parameters
    # handler(Proc):: Incoming data handler should take two arguments:
    #                   * First argument contains command
    #                   * Second argument contains connection used to reply
    def initialize(handler)
      @handler = handler
      @parser = CommandParser.new { |cmd| handler.call(cmd, self) }
    end

    # EventMachine loop callback called whenever there is data coming from the socket
    #
    # === Parameter
    # data(String):: Incoming data
    #
    # === Return
    # true:: Always return true
    def receive_data(data)
      @parser.parse_chunk(data)
      true
    end
   
  end

  # Class which allows listening for data and sending data on sockets
  # This allows ohter processes running on the same machine to send commands to
  # the agent without having to go through RabbitMQ.
  class CommandIO

    include Singleton

    # Is listener currently waiting for input?
    #
    # === Return
    # true:: If 'listen' was last called
    # false:: Otherwise
    def listening
      !@conn.nil?
    end

    # Open command socket and wait for input on it
    # This can only be called again after 'stop_listening' was called
    #
    # === Block
    # The given block should take two arguments:
    #   * First argument will be given the commands sent through the socket
    #     Commands should be serialized using RightScale::CommandSerializer.
    #   * Second argument contains the connection that should be given back to
    #     +reply+ to send reply
    #
    # === Return
    # true:: Always return true
    #
    # === Raise
    # (RightScale::Exceptions::Argument):: If block is missing
    # (RightScale::Exceptions::Application):: If +listen+ has already been called and +stop+ hasn't since
    def listen &block
      raise Exceptions::Argument, 'Missing listener block' unless block_given?
      raise Exceptions::Application, 'Already listening' if listening
      begin
        @conn = EM.start_server('127.0.0.1', RightScale::CommandConstants::SOCKET_PORT, InputHandler, block)
      rescue Exception => e
        RightLinkLog.error("Could not start commands listener: #{e.message}")
      end
      true
    end

    # Stop listening for commands
    # Do nothing if already stopped
    #
    # === Return
    # true:: If command listener was listening
    # false:: Otherwise
    def stop_listening
      res = !@conn.nil?
      if res
        EM.stop_server(@conn)
        @conn = nil
      end
      res
    end

    # Write given data to socket, must be listening
    #
    # === Parameters
    # conn(EM::Connection):: Connection used to send data
    # data(String):: Data that should be written
    #
    # === Return
    # true:: Always return true
    def reply(conn, data)
      conn.send_data(CommandSerializer.dump(data))
      conn.close_connection_after_writing
      true
    end

  end

end
