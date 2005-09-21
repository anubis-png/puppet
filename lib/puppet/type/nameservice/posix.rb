require 'puppet'

module Puppet
    class Type
        def self.posixmethod
            if defined? @posixmethod and @posixmethod
                return @posixmethod
            else
                return @name
            end
        end
    end

    module NameService
        # This is the base module for basically all of the NSS stuff.  It
        # should be able to retrieve the info for almost any system, but
        # it can't create any information on its own.  You need to define
        # a subclass of these classes to actually modify the system.
        module POSIX
            class POSIXState < Puppet::State
                class << self
                    attr_accessor :extender

                    def autogen?
                        if defined? @autogen
                            return @autogen
                        else
                            return false
                        end
                    end

                    def optional?
                        if defined? @optional
                            return @optional
                        else
                            return false
                        end
                    end
                end

                def self.doc
                    if defined? @extender
                        @extender.doc
                    else
                        nil
                    end
                end

                def self.complete
                    mod = "Puppet::State::%s" %
                        self.to_s.sub(/.+::/,'')
                    begin
                        modklass = eval(mod)
                    rescue NameError
                        raise Puppet::Error,
                            "Could not find extender module %s for %s" %
                                [mod, self.to_s]
                    end
                    include modklass

                    self.extender = modklass
                end

                def self.posixmethod
                    if defined? @extender
                        if @extender.respond_to?(:posixmethod)
                            return @extender.posixmethod
                        else
                            return @extender.name
                        end
                    else
                        raise Puppet::DevError,
                            "%s could not retrieve posixmethod" % self
                    end
                end

                def self.name
                    @extender.name
                end

                # we use the POSIX interfaces to retrieve all information,
                # so we don't have to worry about abstracting that across
                # the system
                def retrieve
                    if obj = @parent.getinfo(true)

                        if method = self.class.posixmethod || self.class.name
                            @is = obj.send(method)
                        else
                            raise Puppet::DevError,
                                "%s has no posixmethod" % self.class
                        end
                    else
                        @is = :notfound
                    end
                end

                def sync
                    event = nil
                    # they're in sync some other way
                    if @is == @should
                        return nil
                    end
                    if @is == :notfound
                        self.retrieve
                        if @is == @should
                            return nil
                        end
                    end
                    # if the object needs to be created or deleted,
                    # depend on another method to do it all at once
                    if @is == :notfound or @should == :notfound
                        event = syncname()

                        return event
                        # if the whole object is created at once, just return
                        # an event saying so
                        #if self.class.allatonce?
                        #    return event
                        #end
                    end

                    unless @parent.exists?
                        raise Puppet::DevError,
                            "%s %s does not exist; cannot set %s" %
                            [@parent.class.name, @parent.name, self.class.name]
                    end

                    # this needs to be set either by the individual state
                    # or its parent class
                    cmd = self.modifycmd

                    Puppet.debug "Executing %s" % cmd.inspect

                    output = %x{#{cmd} 2>&1}


                    unless $? == 0
                        raise Puppet::Error, "Could not modify %s on %s %s: %s" %
                            [self.class.name, @parent.class.name,
                                @parent.name, output]
                    end

                    if event
                        return event
                    else
                        return "#{@parent.class.name}_modified".intern
                    end
                end

                private
                def syncname
                    cmd = nil
                    event = nil
                    if @should == :notfound
                        # we need to remove the object...
                        unless @parent.exists?
                            # the group already doesn't exist
                            return nil
                        end

                        # again, needs to be set by the ind. state or its
                        # parent
                        cmd = self.deletecmd
                        type = "delete"
                    else
                        if @parent.exists?
                            return nil
                        end

                        # blah blah, define elsewhere, blah blah
                        cmd = self.addcmd
                        type = "create"
                    end
                    Puppet.debug "Executing %s" % cmd.inspect

                    output = %x{#{cmd} 2>&1}

                    unless $? == 0
                        raise Puppet::Error, "Could not %s %s %s: %s" %
                            [type, @parent.class.name, @parent.name, output]
                    end

                    # we want object creation to show up as one event, 
                    # not many
                    unless self.class.allatonce?
                        if type == "create"
                            @parent.eachstate { |state|
                                state.sync
                                state.retrieve
                            }
                        end
                    end

                    return "#{@parent.class.name}_#{type}d".intern
                end
            end
        end
    end
end