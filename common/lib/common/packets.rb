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

# Hack to replace Nanite namespace from downrev nanites with RightScale
module JSON
  class << self
    def parse(source, opts = {})
      if source =~ /(.*)json_class":"Nanite::(.*)/
        JSON.parser.new( Regexp.last_match(1) + 'json_class":"RightScale::' + Regexp.last_match(2), opts).parse
      else
        JSON.parser.new(source, opts).parse
      end
    end
  end
end

module RightScale

  # Base class for all nanite packets,
  # knows how to dump itself to JSON
  class Packet

    attr_accessor :size

    def initialize
      raise NotImplementedError.new("#{self.class.name} is an abstract class.")
    end

    def to_json(*a)
      # Hack to override RightScale namespace with Nanite for downward compatibility
      class_name = self.class.name
      if class_name =~ /^RightScale::(.*)/
        class_name = "Nanite::" + Regexp.last_match(1)
      end

      js = {
        'json_class'   => class_name,
        'data'         => instance_variables.inject({}) {|m,ivar| m[ivar.to_s.sub(/@/,'')] = instance_variable_get(ivar); m }
      }.to_json(*a)
      js = js.chop + ",\"size\":#{js.size}}"
      js
    end

    # Log representation
    def to_s(filter=nil)
      res = "[#{ self.class.to_s.split('::').last.
        gsub(/([A-Z]+)([A-Z][a-z])/,'\1_\2').
        gsub(/([a-z\d])([A-Z])/,'\1_\2').
        downcase }]"
      res += " (#{size.to_s.gsub(/(\d)(?=(\d\d\d)+(?!\d))/, "\\1,")} bytes)" if size && !size.to_s.empty?
      res
    end

    # Log friendly name for given agent id
    def id_to_s(id)
      case id
        when /^mapper-/ then 'mapper'
        when /^nanite-(.*)/ then Regexp.last_match(1)
        else id
      end
    end

    # Return target to be used for encrypting the packet
    def target_for_encryption
      nil
    end

    # Token used to trace execution of operation across multiple packets, may be nil 
    def trace
      audit_id = self.respond_to?(:payload) && payload.is_a?(Hash) && payload['audit_id']  
      tok = self.respond_to?(:token) && token
      tr = ''
      if audit_id || tok
        tr = '<'        
        if audit_id 
          tr += audit_id.to_s
          tr += ':' if tok
        end
        tr += tok if tok
        tr += '>'
      end
      tr  
    end

  end # Packet

  # packet that means a work request from mapper
  # to actor node
  #
  # type     is a service name
  # payload  is arbitrary data that is transferred from mapper to actor
  #
  # Options:
  # from      is sender identity
  # scope     define behavior that should be used to resolve tag based routing
  # token     is a generated request id that mapper uses to identify replies
  # reply_to  is identity of the node actor replies to, usually a mapper itself
  # selector  is the selector used to route the request
  # target    is the target nanite for the request
  # persistent signifies if this request should be saved to persistent storage by the AMQP broker
  class Request < Packet

    attr_accessor :from, :scope, :payload, :type, :token, :reply_to, :selector, :target, :persistent, :tags

    DEFAULT_OPTIONS = {:selector => :least_loaded}

    def initialize(type, payload, opts={}, size=nil)
      opts = DEFAULT_OPTIONS.merge(opts)
      @type       = type
      @payload    = payload
      @size       = size
      @from       = opts[:from]
      @scope      = opts[:scope]
      @token      = opts[:token]
      @reply_to   = opts[:reply_to]
      @selector   = opts[:selector]
      @target     = opts[:target]
      @persistent = opts[:persistent]
      @tags       = opts[:tags] || []
    end

    def self.json_create(o)
      i = o['data']
      new(i['type'], i['payload'], { :from       => i['from'],       :scope    => i['scope'],
                                     :token      => i['token'],      :reply_to => i['reply_to'],
                                     :selector   => i['selector'],   :target   => i['target'],   
                                     :persistent => i['persistent'], :tags     => i['tags'] },
                                   o['size'])
    end

    def to_s(filter=nil)
      log_msg = "#{super} #{trace} #{type}"
      log_msg += " from #{id_to_s(from)}" if filter.nil? || filter.include?(:from)
      log_msg += " with scope #{scope}" if scope && (filter.nil? || filter.include?(:scope))
      log_msg += " target #{id_to_s(target)}" if target && (filter.nil? || filter.include?(:target))
      log_msg += ", reply_to #{id_to_s(reply_to)}" if reply_to && (filter.nil? || filter.include?(:reply_to))
      log_msg += ", tags #{tags.inspect}" if tags && !tags.empty? && (filter.nil? || filter.include?(:tags))
      log_msg += ", payload #{payload.inspect}" if filter.nil? || filter.include?(:payload)
      log_msg
    end

    # Return target to be used for encrypting the packet
    def target_for_encryption
      @target
    end

  end # Request

  # packet that means a work push from mapper
  # to actor node
  #
  # type     is a service name
  # payload  is arbitrary data that is transferred from mapper to actor
  #
  # Options:
  # from      is sender identity
  # scope     define behavior that should be used to resolve tag based routing
  # token     is a generated request id that mapper uses to identify replies
  # selector  is the selector used to route the request
  # target    is the target nanite for the request
  # persistent signifies if this request should be saved to persistent storage by the AMQP broker
  class Push < Packet

    attr_accessor :from, :scope, :payload, :type, :token, :selector, :target, :persistent, :tags

    DEFAULT_OPTIONS = {:selector => :least_loaded}

    def initialize(type, payload, opts={}, size=nil)
      opts = DEFAULT_OPTIONS.merge(opts)
      @type       = type
      @payload    = payload
      @size       = size
      @from       = opts[:from]
      @scope      = opts[:scope]
      @token      = opts[:token]
      @selector   = opts[:selector]
      @target     = opts[:target]
      @persistent = opts[:persistent]
      @tags       = opts[:tags] || []
    end

    def self.json_create(o)
      i = o['data']
      new(i['type'], i['payload'], { :from   => i['from'],   :scope      => i['scope'],
                                     :token  => i['token'],  :selector   => i['selector'],
                                     :target => i['target'], :persistent => i['persistent'],
                                     :tags   => i['tags'] },
                                   o['size'])
    end

    def to_s(filter=nil)
      log_msg = "#{super} #{trace} #{type}"
      log_msg += " from #{id_to_s(from)}" if filter.nil? || filter.include?(:from)
      log_msg += " with scope #{scope}" if scope && (filter.nil? || filter.include?(:scope))
      log_msg += ", target #{id_to_s(target)}" if target && (filter.nil? || filter.include?(:target))
      log_msg += ", tags #{tags.inspect}" if tags && !tags.empty? && (filter.nil? || filter.include?(:tags))
      log_msg += ", payload #{payload.inspect}" if filter.nil? || filter.include?(:payload)
      log_msg
    end

    # Return target to be used for encrypting the packet
    def target_for_encryption
      @target
    end

  end # Push

  # Deprecated: instead use Request of type /mapper/list_agents with :tags and :agent_ids in payload
  #
  # Tag query: retrieve agents with specified tags and/or ids
  #
  # Options:
  # from  is sender identity
  # opts  Hash of options, two options are supported, at least one must be set:
  #       :tags is an array of tags defining a query that returned agents tags must match
  #       :agent_ids is an array of ids of agents that should be returned
  class TagQuery < Packet

    attr_accessor :from, :token, :agent_ids, :tags, :persistent

    def initialize(from, opts, size=nil)
      @from       = from
      @token      = opts[:token]
      @agent_ids  = opts[:agent_ids]
      @tags       = opts[:tags]
      @persistent = opts[:persistent]
      @size       = size
    end

    def self.json_create(o)
      i = o['data']
      new(i['from'], { :token => i['token'], :agent_ids => i['agent_ids'],
                       :tags => i['tags'],   :persistent => i['persistent'] },
                     o['size'])
    end

    def to_s(filter=nil)
      log_msg = "#{super} #{trace}"
      log_msg += " from #{id_to_s(from)}" if filter.nil? || filter.include?(:from)
      log_msg += " agent_ids #{agent_ids.inspect}" 
      log_msg += " tags: #{tags.inspect}" 
      log_msg
    end

  end # TagQuery

  # packet that means a work result notification sent from actor to mapper
  #
  # from     is sender identity
  # results  is arbitrary data that is transferred from actor, a result of actor's work
  # token    is a generated request id that mapper uses to identify replies
  # to       is identity of the node result should be delivered to
  class Result < Packet

    attr_accessor :token, :results, :to, :from

    def initialize(token, to, results, from, size=nil)
      @token = token
      @to = to
      @from = from
      @results = results
      @size = size
    end

    def self.json_create(o)
      i = o['data']
      new(i['token'], i['to'], i['results'], i['from'], o['size'])
    end

    def to_s(filter=nil)
      log_msg = "#{super} #{trace}"
      log_msg += " from #{id_to_s(from)}" if filter.nil? || filter.include?(:from)
      log_msg += " to #{id_to_s(to)}" if filter.nil? || filter.include?(:to)
      log_msg += " results: #{results.inspect}" if filter.nil? || filter.include?(:results)
      log_msg
    end

    # Return target to be used for encrypting the packet
    def target_for_encryption
      @to
    end

  end # Result

  # packet that means an availability notification sent from agent to mapper
  #
  # from         is sender identity
  # services     is a list of services provided by the node
  # status       is a load of the node by default, but may be any criteria
  #              agent may use to report it's availability, load, etc
  # tags         is a list of tags associated with this service
  # shared_queue is the name of a queue shared between this agent and another
  class Register < Packet

    attr_accessor :identity, :services, :status, :tags, :shared_queue

    def initialize(identity, services, status, tags, shared_queue=nil, size=nil)
      @status       = status
      @tags         = tags
      @identity     = identity
      @services     = services
      @shared_queue = shared_queue
      @size         = size
    end

    def self.json_create(o)
      i = o['data']
      new(i['identity'], i['services'], i['status'], i['tags'], i['shared_queue'], o['size'])
    end

    def to_s
      log_msg = "#{super} #{id_to_s(identity)}"
      log_msg += ", shared_queue: #{shared_queue}" if shared_queue
      log_msg += ", services: #{services.join(', ')}" if services && !services.empty?
      log_msg += ", tags: #{tags.join(', ')}" if tags && !tags.empty?
      log_msg
    end

  end # Register

  # packet that means deregister an agent from the mappers
  #
  # from     is sender identity
  class UnRegister < Packet

    attr_accessor :identity

    def initialize(identity, size=nil)
      @identity = identity
      @size = size
    end

    def self.json_create(o)
      i = o['data']
      new(i['identity'], o['size'])
    end
  
    def to_s
      "#{super} #{id_to_s(identity)}"
    end

  end # UnRegister

  # heartbeat packet
  #
  # identity is sender's identity
  # status   is sender's status (see Register packet documentation)
  class Ping < Packet

    attr_accessor :identity, :status

    def initialize(identity, status, size=nil)
      @status   = status
      @identity = identity
      @size     = size
    end

    def self.json_create(o)
      i = o['data']
      new(i['identity'], i['status'], o['size'])
    end

    def to_s
      "#{super} #{id_to_s(identity)} status #{status}"
    end

  end # Ping

  # packet that is sent by workers to the mapper
  # when worker initially comes online to advertise
  # it's services
  class Advertise < Packet

    def initialize(size=nil)
      @size = size
    end
    
    def self.json_create(o)
      new(o['size'])
    end

  end # Advertise

  # packet that is sent by agents to the mapper
  # to update their tags
  class TagUpdate < Packet

    attr_accessor :identity, :new_tags, :obsolete_tags

    def initialize(identity, new_tags, obsolete_tags, size=nil)
      @identity      = identity
      @new_tags      = new_tags
      @obsolete_tags = obsolete_tags
      @size          = size
    end

    def self.json_create(o)
      i = o['data']
      new(i['identity'], i['new_tags'], i['obsolete_tags'], o['size'])
    end

    def to_s
      log_msg = "#{super} #{id_to_s(identity)}"
      log_msg += ", new tags: #{new_tags.join(', ')}" if new_tags && !new_tags.empty?
      log_msg += ", obsolete tags: #{obsolete_tags.join(', ')}" if obsolete_tags && !obsolete_tags.empty?
      log_msg
    end

  end # TagUpdate

end # RightScale

