# A Puppet::Type class to manage cron jobs.  Some abstraction is done,
# so that different platforms' versions of +crontab+ all work equivalently.

require 'etc'
require 'facter'
require 'puppet/type/state'

module Puppet
    # The Puppet::CronType modules are responsible for the actual abstraction.
    # They must implement three module functions: +read+, +write+, and +remove+,
    # analogous to the three flags accepted by most implementations of +crontab+.
    # All of these methods require the user name to be passed in.
    #
    # These modules operate on the strings that are ore become the cron tabs --
    # they do not have any semantic understanding of what they are reading or
    # writing.
    module CronType
        # Retrieve the uid of a user.  This is duplication of code, but the unless
        # I start using Puppet::Type::User objects here, it's a much better design.
        def self.uid(user)
            begin
                return Etc.getpwnam(user).uid
            rescue ArgumentError
                raise Puppet::Error, "User %s not found" % user
            end
        end

        # This module covers nearly everyone; SunOS is only known exception so far.
        module Default
            # Only add the -u flag when the user is different.  Fedora apparently
            # does not think I should be allowed to set the user to myself.
            def self.cmdbase(user)
                uid = CronType.uid(user)
                cmd = nil
                if uid == Process.uid
                    return "crontab"
                else
                    return "crontab -u #{user}"
                end
            end

            # Read a specific user's cron tab.
            def self.read(user)
                tab = %x{#{self.cmdbase(user)} -l 2>/dev/null}
            end

            # Remove a specific user's cron tab.
            def self.remove(user)
                %x{#{self.cmdbase(user)} -r 2>/dev/null}
            end

            # Overwrite a specific user's cron tab; must be passed the user name
            # and the text with which to create the cron tab.
            def self.write(user, text)
                IO.popen("#{self.cmdbase(user)} -", "w") { |p|
                    p.print text
                }
            end
        end

        # SunOS has completely different cron commands; this module implements
        # its versions.
        module SunOS
            # Read a specific user's cron tab.
            def self.read(user)
                Puppet.asuser(user) {
                    %x{crontab -l 2>/dev/null}
                }
            end

            # Remove a specific user's cron tab.
            def self.remove(user)
                Puppet.asuser(user) {
                    %x{crontab -r 2>/dev/null}
                }
            end

            # Overwrite a specific user's cron tab; must be passed the user name
            # and the text with which to create the cron tab.
            def self.write(user, text)
                Puppet.asuser(user) {
                    IO.popen("crontab", "w") { |p|
                        p.print text
                    }
                }
            end
        end
    end

    class State
        # This is Cron's single state.  Somewhat uniquely, this state does not
        # actually change anything -- it just calls +@parent.sync+, which writes
        # out the whole cron tab for the user in question.  There is no real way
        # to change individual cron jobs without rewriting the entire cron file.
        #
        # Note that this means that managing many cron jobs for a given user
        # could currently result in multiple write sessions for that user.
        class CronCommand < Puppet::State
            @name = :command
            @doc = "The command to execute in the cron job.  The environment
                provided to the command varies by local system rules, and it is
                best to always provide a fully qualified command.  The user's
                profile is not sourced when the command is run, so if the
                user's environment is desired it should be sourced manually."

            # Normally this would retrieve the current value, but our state is not
            # actually capable of doing so.  The Cron class does the actual tab
            # retrieval, so all this method does is default to :notfound for @is.
            def retrieve
                unless defined? @is and ! @is.nil?
                    @is = :notfound
                end
            end

            # Determine whether the cron job should be destroyed, and figure
            # out which event to return.  Finally, call @parent.sync to write the
            # cron tab.
            def sync
                @parent.store

                event = nil
                if @is == :notfound
                    #@is = @should
                    event = :cron_created
                elsif @should == :notfound
                    # FIXME I need to actually delete the cronjob...
                    @parent.destroy
                    event = :cron_deleted
                elsif @should == @is
                    Puppet.err "Uh, they're both %s" % @should
                    return nil
                else
                    #@is = @should
                    Puppet.err "@is is %s" % @is
                    event = :cron_changed
                end

                @parent.store
                
                return event
            end
        end
    end

    class Type
        # Model the actual cron jobs.  Supports all of the normal cron job fields
        # as parameters, with the 'command' as the single state.  Also requires a
        # completely symbolic 'name' paremeter, which gets written to the file
        # and is used to manage the job.
        class Cron < Type
            @states = [
                Puppet::State::CronCommand
            ]

            @parameters = [
                :name,
                :user,
                :minute,
                :hour,
                :weekday,
                :month,
                :monthday
            ]

            @paramdoc[:name] = "The symbolic name of the cron job.  This name
                is used for human reference only."
            @paramdoc[:user] = "The user to run the command as.  This user must
                be allowed to run cron jobs, which is not currently checked by
                Puppet."
            @paramdoc[:minute] = "The minute at which to run the cron job.
                Optional; if specified, must be between 0 and 59, inclusive."
            @paramdoc[:hour] = "The hour at which to run the cron job. Optional;
                if specified, must be between 0 and 23, inclusive."
            @paramdoc[:weekday] = "The weekday on which to run the command.
                Optional; if specified, must be between 0 and 6, inclusive, with
                0 being Sunday, or must be the name of the day (e.g., Tuesday)."
            @paramdoc[:month] = "The month of the year.  Optional; if specified
                must be between 1 and 12 or the month name (e.g., December)."
            @paramdoc[:monthday] = "The day of the month on which to run the
                command.  Optional; if specified, must be between 1 and 31."

            @doc = "Installs and manages cron jobs.  All fields except the command 
                and the user are optional, although specifying no periodic
                fields would result in the command being executed every
                minute.  While the name of the cron job is not part of the actual
                job, it is used by Puppet to store and retrieve it.  If you specify
                a cron job that matches an existing job in every way except name,
                then the jobs will be considered equivalent and the new name will
                be permanently associated with that job.  Once this association is
                made and synced to disk, you can then manage the job normally."
            @name = :cron
            @namevar = :name

            @loaded = {}

            @synced = {}

            @instances = {}

            @@weekdays = %w{sunday monday tuesday wednesday thursday friday saturday}

            @@months = %w{january february march april may june july
                august september october november december}

            case Facter["operatingsystem"].value
            when "SunOS":
                @crontype = Puppet::CronType::SunOS
            else
                @crontype = Puppet::CronType::Default
            end

            class << self
                attr_accessor :crontype
            end

            attr_accessor :uid

            # Override the Puppet::Type#[]= method so that we can store the instances
            # in per-user arrays.  Then just call +super+.
            def self.[]=(name, object)
                self.instance(object)
                super
            end

            # In addition to removing the instances in @objects, Cron has to remove
            # per-user cron tab information.
            def self.clear
                @instances = {}
                @loaded = {}
                @synced = {}
                super
            end

            # Override the default Puppet::Type method, because instances
            # also need to be deleted from the @instances hash
            def self.delete(child)
                if @instances.include?(child[:user])
                    if @instances[child[:user]].include?(child)
                        @instances[child[:user]].delete(child)
                    end
                end
                super
            end

            # Return the fields found in the cron tab.
            def self.fields
                return [:minute, :hour, :monthday, :month, :weekday, :command]
            end

            # Return the header placed at the top of each generated file, warning
            # users that modifying this file manually is probably a bad idea.
            def self.header
%{#This file was autogenerated at #{Time.now} by puppet.  While it
# can still be managed manually, it is definitely not recommended.
# Note particularly that the comments starting with 'Puppet Name' should
# not be deleted, as doing so could cause duplicate cron jobs.\n}
            end

            # Store a new instance of a cron job.  Called from Cron#initialize.
            def self.instance(obj)
                user = obj[:user]
                if @instances.include?(user)
                    unless @instances[obj[:user]].include?(obj)
                        @instances[obj[:user]] << obj
                    end
                else
                    @instances[obj[:user]] = [obj]
                end
            end

            # Parse a user's cron job into individual cron objects.
            #
            # Autogenerates names for any jobs that don't already have one; these
            # names will get written back to the file.
            #
            # This method also stores existing comments, and it stores all cron
            # jobs in order, mostly so that comments are retained in the order
            # they were written and in proximity to the same jobs.
            def self.parse(user, text)
                count = 0
                hash = {}
                name = nil
                unless @instances.include?(user)
                    @instances[user] = []
                end
                text.chomp.split("\n").each { |line|
                    case line
                    when /^# Puppet Name: (\w+)$/: name = $1
                    when /^#/:
                        # add other comments to the list as they are
                        @instances[user] << line 
                    else
                        ary = line.split(" ")
                        fields().each { |param|
                            value = ary.shift
                            unless value == "*"
                                hash[param] = value
                            end
                        }

                        if ary.length > 0
                            hash[:command] += " " + ary.join(" ")
                        end
                        cron = nil
                        unless name
                            Puppet.info "Autogenerating name for %s" % hash[:command]
                            name = "cron-%s" % hash.object_id
                        end

                        unless hash.include?(:command)
                            raise Puppet::DevError, "No command for %s" % name
                        end
                        # if the cron already exists with that name...
                        if cron = Puppet::Type::Cron[hash[:command]]
                            # do nothing...
                        elsif tmp = @instances[user].reject { |obj|
                                    ! obj.is_a?(Cron)
                                }.find { |obj|
                                    obj.should(:command) == hash[:command]
                                }
                            # if we can find a cron whose spec exactly matches

                            # we now have a cron job whose command exactly matches
                            # let's see if the other fields match
                            txt = tmp.to_cron.sub(/#.+\n/,'')

                            if txt == line
                                cron = tmp
                            end
                        else
                            # create a new cron job, since no existing one
                            # seems to match
                            cron = Puppet::Type::Cron.create(
                                :name => name
                            )
                        end

                        hash.each { |param, value|
                            cron.is = [param, value]
                        }
                        hash.clear
                        name = nil
                        count += 1
                    end
                }
            end

            # Retrieve a given user's cron job, using the @crontype's +retrieve+
            # method.  Returns nil if there was no cron job; else, returns the
            # number of cron instances found.
            def self.retrieve(user)
                #%x{crontab -u #{user} -l 2>/dev/null}.split("\n").each { |line|
                text = @crontype.read(user)
                if $? != 0
                    # there is no cron file
                    return nil
                else
                    self.parse(user, text)
                end

                @loaded[user] = Time.now
            end

            # Store the user's cron tab.  Collects the text of the new tab and
            # sends it to the +@crontype+ module's +write+ function.  Also adds
            # header warning users not to modify the file directly.
            def self.store(user)
                if @instances.include?(user)
                    @crontype.write(user, self.header + self.tab(user))
                    @synced[user] = Time.now
                else
                    Puppet.notice "No cron instances for %s" % user
                end
            end

            # Collect all Cron instances for a given user and convert them
            # into literal text.
            def self.tab(user)
                if @instances.include?(user)
                    return @instances[user].collect { |obj|
                        if obj.is_a?(Cron)
                            obj.to_cron
                        else
                            obj.to_s
                        end
                    }.join("\n") + "\n"
                else
                    Puppet.notice "No cron instances for %s" % user
                end
            end

            # Return the last time a given user's cron tab was loaded.  Could
            # be used for reducing writes, but currently is not.
            def self.loaded?(user)
                if @loaded.include?(user)
                    return @loaded[user]
                else
                    return nil
                end
            end

            # Because the current value is retrieved by the +@crontype+ module,
            # the +is+ value on the state is set by an outside party.  Cron is
            # currently the only class that needs this, so this method is provided
            # specifically for it.
            def is=(ary)
                param, value = ary
                if param.is_a?(String)
                    param = param.intern
                end
                if self.class.validstate?(param)
                    self.newstate(param)
                    @states[param].is = value
                else
                    self[param] = value
                end
            end

            # A method used to do parameter input handling.  Converts integers in
            # string form to actual integers, and returns the value if it's an integer
            # or false if it's just a normal string.
            def numfix(num)
                if num =~ /^\d+$/
                    return num.to_i
                elsif num.is_a?(Integer)
                    return num
                else
                    return false
                end
            end

            # Verify that a number is within the specified limits.  Return the
            # number if it is, or false if it is not.
            def limitcheck(num, lower, upper)
                if num >= lower and num <= upper
                    return num
                else
                    return false
                end
            end

            # Verify that a value falls within the specified array.  Does case
            # insensitive matching, and supports matching either the entire word
            # or the first three letters of the word.
            def alphacheck(value, ary)
                tmp = value.downcase
                if tmp.length == 3
                    ary.each_with_index { |name, index|
                        if name =~ /#{tmp}/i
                            return index
                        end
                    }
                else
                    if ary.include?(tmp)
                        return ary.index(tmp)
                    end
                end

                return false
            end

            # The method that does all of the actual parameter value checking; called
            # by all of the +param<name>=+ methods.  Requires the value, type, and
            # bounds, and optionally supports a boolean of whether to do alpha
            # checking, and if so requires the ary against which to do the checking.
            def parameter(values, type, lower, upper, alpha = nil, ary = nil)
                unless values.is_a?(Array)
                    if values =~ /,/
                        values = values.split(/,/)
                    else
                        values = [values]
                    end
                end

                @parameters[type] = values.collect { |value|
                    retval = nil
                    if num = numfix(value)
                        retval = limitcheck(num, lower, upper)
                    elsif alpha
                        retval = alphacheck(value, ary)
                    end

                    if retval
                        @parameters[type] = retval
                    else
                        raise Puppet::Error, "%s is not a valid %s" %
                            [value, type]
                    end
                }
            end

            def paramminute=(value)
                parameter(value, :minute, 0, 59)
            end

            def paramhour=(value)
                parameter(value, :hour, 0, 23)
            end

            def paramweekday=(value)
                parameter(value, :weekday, 0, 6, true, @@weekdays)
            end

            def parammonth=(value)
                parameter(value, :month, 1, 12, true, @@months)
            end

            def parammonthday=(value)
                parameter(value, :monthday, 1, 31)
            end

            def paramuser=(user)
                require 'etc'

                begin
                    obj = Etc.getpwnam(user)
                    @uid = obj.uid
                rescue ArgumentError
                    raise Puppet::Error, "User %s not found" % user
                end
                @parameters[:user] = user
            end

            # Override the default Puppet::Type method because we need to call
            # the +@crontype+ retrieve method.
            def retrieve
                unless @parameters.include?(:user)
                    raise Puppet::Error, "You must specify the cron user"
                end

                self.class.retrieve(@parameters[:user])
                @states[:command].retrieve
            end

            # Write the entire user's cron tab out.
            def store
                self.class.store(@parameters[:user])
            end

            # Convert the current object a cron-style string.  Adds the cron name
            # as a comment above the cron job, in the form '# Puppet Name: <name>'.
            def to_cron
                hash = {:command => @states[:command].should || @states[:command].is }
                self.class.fields().reject { |f| f == :command }.each { |param|
                    hash[param] = @parameters[param] || "*"
                }

                return "# Puppet Name: %s\n" % self.name +
                    self.class.fields.collect { |f|
                        if hash[f].is_a?(Array)
                            hash[f].join(",")
                        else
                            hash[f]
                        end
                    }.join(" ")
            end
        end
    end
end

# $Id$