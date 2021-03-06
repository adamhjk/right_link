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
#

module RightScale
  
  # Software repository
  # May or may not be frozen depending on whether frozen_date is set
  class SoftwareRepositoryInstantiation

    include Serializable

    # (String) Software repository name
    attr_accessor :name
    
    # (Array) Software repository base URL
    attr_accessor :base_urls
    
    # (Date) Frozen date if any
    attr_accessor :frozen_date
        
    def initialize(*args)
      @name        = args[0] if args.size > 0
      @base_urls   = args[1] if args.size > 1
      @frozen_date = args[2] if args.size > 2
    end

    # Human readable representation
    #
    # === Return
    # Text representing repository instantiation that can be audited
    def to_s
      res = "#{name} #{base_urls.inspect}"
      frozen_date ? res + " @ #{frozen_date.to_s}" : res
    end
    
    # Array of serialized fields given to constructor
    def serialized_members
      [ @name, @base_urls, @frozen_date ]
    end
  end
end
