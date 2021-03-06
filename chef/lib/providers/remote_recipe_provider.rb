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

class Chef

  class Provider

    # RemoteRecipe chef provider.
    class RemoteRecipe < Chef::Provider

      # No concept of a 'current' resource for RemoteRecipe execution, this is a no-op
      #
      # === Return
      # true:: Always return true
      def load_current_resource
        true
      end

      # Actually run RemoteRecipe
      #
      # === Return
      # true:: Always return true
      def action_run
        tags = @new_resource.recipients_tags
        attributes = { :remote_recipe => { :tags => tags,
                                           :from => RightScale::MapperProxy.instance.identity } }
        attributes.merge!(@new_resource.attributes) if @new_resource.attributes
        options = { :recipe => @new_resource.recipe, :json => attributes.to_json }
        @new_resource.recipients.each do |target|
          RightScale::RequestForwarder.push('/instance_scheduler/execute',
                                            options, 
                                            :target => target)
        end if @new_resource.recipients
        if tags && !tags.empty?
          selector = (@new_resource.scope == :single ? :least_loaded : :all)
          RightScale::RequestForwarder.push('/instance_scheduler/execute', options,
                                   :tags => tags, :selector => selector)
        end
        true
      end

    end

  end

end
