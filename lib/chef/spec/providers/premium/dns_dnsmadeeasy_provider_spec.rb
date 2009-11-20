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

require File.join(File.dirname(__FILE__), '..', '..', 'spec_helper')

describe Chef::Provider::DnsMadeEasy do
  before(:each) do
    @node = flexmock('Chef::Node')
    @node.should_ignore_missing
    @new_resource = Chef::Resource::Dns.new("www.testsite.com")
    @new_resource.user "testuser"
    @new_resource.passwd "testpasswd"
    @new_resource.ip_address "1.1.1.1"
  end
  
  it "should be registered with the default platform hash" do
    Chef::Platform.platforms[:default][:dns].should_not be_nil
  end

  it "should return a Chef::Provider::Dns object" do
    provider = Chef::Provider::DnsMadeEasy.new(@node, @new_resource)
    provider.should be_a_kind_of(Chef::Provider::DnsMadeEasy)
  end

  it "should log not raise an exception if success" do
    flexmock(Chef::Log).should_receive(:info).twice
    flexmock(Chef::Log).should_receive(:debug)
    provider = Chef::Provider::DnsMadeEasy.new(@node, @new_resource)
    flexmock(provider).should_receive(:post_change).once.and_return('success')
    provider.action_register
  end

  it "should return raise an exception if post fails" do
    flexmock(Chef::Log).should_receive(:info)
    flexmock(Chef::Log).should_receive(:debug)
    provider = Chef::Provider::DnsMadeEasy.new(@node, @new_resource)
    flexmock(provider).should_receive(:post_change).once.and_return('failure')
    lambda{ provider.action_register }.should raise_error(Chef::Exceptions::Dns)
  end
  
end



