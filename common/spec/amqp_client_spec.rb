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

require File.join(File.dirname(__FILE__), 'spec_helper')
require File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'lib', 'agent_deployer')
require File.join(File.dirname(__FILE__), '..', '..', 'scripts', 'lib', 'agent_controller')

describe AMQP::Client do
  context 'with an incorrect AMQP password' do
    class SUT
      include AMQP::Client

      attr_accessor :reconnecting, :settings, :channels
    end

    before(:each) do
      @sut = flexmock(SUT.new)
      @sut.reconnecting = false
      @sut.settings = {:host=>'testhost', :port=>'12345'}
      @sut.channels = {}

      @sut.should_receive(:initialize)
    end

    context 'and no :retry' do
      it 'should reconnect immediately' do
        flexmock(EM).should_receive(:reconnect).once
        flexmock(EM).should_receive(:add_timer).never

        @sut.reconnect()
      end
    end

    context 'and a :retry of false' do
      it 'should not schedule a reconnect' do
        @sut.settings[:retry] = false

        flexmock(EM).should_receive(:reconnect).never
        flexmock(EM).should_receive(:add_timer).never

        lambda { @sut.reconnect }.should raise_error(StandardError)
      end
    end

    context 'and a :retry of true' do
      it 'should reconnect immediately' do
        @sut.settings[:retry] = true

        flexmock(EM).should_receive(:reconnect).once
        flexmock(EM).should_receive(:add_timer).never

        @sut.reconnect()
      end
    end

    context 'and a :retry of 15 seconds' do
      it 'should schedule a reconnect attempt in 15s' do
        @sut.settings[:retry] = 15

        flexmock(EM).should_receive(:reconnect).never
        flexmock(EM).should_receive(:add_timer).with(15, Proc)

        @sut.reconnect()
      end
    end

    context 'and a :retry containing a Proc that returns 30' do
      it 'should schedule a reconnect attempt in 30s' do
        @sut.settings[:retry] = Proc.new {30}

        flexmock(EM).should_receive(:reconnect).never
        flexmock(EM).should_receive(:add_timer).with(30, Proc)

        @sut.reconnect()
      end
    end

  end

end
