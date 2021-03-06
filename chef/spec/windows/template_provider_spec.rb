# Copyright (c) 2010 RightScale Inc
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

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))

# FIX: rake spec should check parent directory name?
if RightScale::RightLinkConfig[:platform].windows?

  require 'fileutils'
  require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'mock_auditor_proxy'))
  require File.normalize_path(File.join(File.dirname(__FILE__), '..', 'chef_runner'))

  module TemplateProviderSpec
    TEST_TEMP_PATH = File.normalize_path(File.join(Dir.tmpdir, "template-provider-spec-3FEFA392-2624-4e6d-8279-7D0BEB1CC7A2")).gsub("\\", "/")
    TEST_COOKBOOKS_PATH = RightScale::Test::ChefRunner.get_cookbooks_path(TEST_TEMP_PATH)
    TEST_COOKBOOK_PATH = File.join(TEST_COOKBOOKS_PATH, 'test')
    SOURCE_FILE_PATH = File.join(TEST_COOKBOOK_PATH, 'templates', 'default', 'test.erb')
    TEST_FILE_PATH = File.join(TEST_TEMP_PATH, 'data', 'template_file.txt')

    def create_cookbook
      RightScale::Test::ChefRunner.create_cookbook(
        TEST_TEMP_PATH,
          {
            :create_templated_file_recipe => (
<<EOF
template "#{TEST_FILE_PATH}" do
  source "#{File.basename(SOURCE_FILE_PATH)}"
  mode 0440
  variables( :var1 => 'Chef', :var2 => 'Windows' )
end
EOF
          )
        }
      )

      # template source.
      FileUtils.mkdir_p(File.dirname(SOURCE_FILE_PATH))
      source_text =
<<EOF
<%= @var1 %> can work in <%= @var2 %>.
EOF
      File.open(SOURCE_FILE_PATH, "w") { |f| f.write(source_text) }
    end

    module_function :create_cookbook

    def cleanup
      (FileUtils.rm_rf(TEST_TEMP_PATH) rescue nil) if File.directory?(TEST_TEMP_PATH)
    end

    module_function :cleanup
  end

  describe Chef::Provider::Template do

    before(:all) do
      @old_logger = Chef::Log.logger
      TemplateProviderSpec.create_cookbook
      FileUtils.mkdir_p(File.dirname(TemplateProviderSpec::TEST_FILE_PATH))
    end

    before(:each) do
      Chef::Log.logger = RightScale::Test::MockAuditorProxy.new
    end

    after(:all) do
      Chef::Log.logger = @old_logger
      TemplateProviderSpec.cleanup
    end

    it "should create templated files on windows" do
      runner = lambda {
        RightScale::Test::ChefRunner.run_chef(
          TemplateProviderSpec::TEST_COOKBOOKS_PATH,
          'test::create_templated_file_recipe') }
      runner.call.should == true
      File.file?(TemplateProviderSpec::TEST_FILE_PATH).should == true
      message = File.read(TemplateProviderSpec::TEST_FILE_PATH)
      message.chomp.should == "Chef can work in Windows."
      File.delete(TemplateProviderSpec::TEST_FILE_PATH)
    end

  end

end # if windows?
