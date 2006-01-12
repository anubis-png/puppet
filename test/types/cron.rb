# Test cron job creation, modification, and destruction

if __FILE__ == $0
    $:.unshift '..'
    $:.unshift '../../lib'
    $puppetbase = "../../../../language/trunk"
end

require 'puppettest'
require 'puppet'
require 'puppet/type/cron'
require 'test/unit'
require 'facter'


# Here we just want to unit-test our cron type, to verify that 
#class TestCronType < Test::Unit::TestCase
#	include TestPuppet
#
#
#end

class TestCron < Test::Unit::TestCase
	include TestPuppet
    def setup
        super
        # retrieve the user name
        id = %x{id}.chomp
        if id =~ /uid=\d+\(([^\)]+)\)/
            @me = $1
        else
            puts id
        end
        unless defined? @me
            raise "Could not retrieve user name; 'id' did not work"
        end

        # god i'm lazy
        @crontype = Puppet.type(:cron)

        # Here we just create a fake cron type that answers to all of the methods
        # but does not modify our actual system.
        unless defined? @fakecrontype
            @fakecrontype = Class.new {
                @tabs = Hash.new("")
                def self.clear
                    @tabs = Hash.new("")
                end

                def self.read(user)
                    @tabs[user]
                end

                def self.write(user, text)
                    @tabs[user] = text
                end

                def self.remove(user)
                    @tabs.delete(user)
                end
            }

            @oldcrontype = @crontype.crontype
            @crontype.crontype = @fakecrontype
        end
    end

    def teardown
        @crontype.crontype = @oldcrontype
        @fakecrontype.clear
        super
    end

    # Back up the user's existing cron tab if they have one.
    def cronback
        tab = nil
        assert_nothing_raised {
            tab = Puppet.type(:cron).crontype.read(@me)
        }

        if $? == 0
            @currenttab = tab
        else
            @currenttab = nil
        end
    end

    # Restore the cron tab to its original form.
    def cronrestore
        assert_nothing_raised {
            if @currenttab
                @crontype.crontype.write(@me, @currenttab)
            else
                @crontype.crontype.remove(@me)
            end
        }
    end

    # Create a cron job with all fields filled in.
    def mkcron(name)
        cron = nil
        assert_nothing_raised {
            cron = @crontype.create(
                :command => "date > %s/crontest%s" % [tmpdir(), name],
                :name => name,
                :user => @me,
                :minute => rand(59),
                :month => "1",
                :monthday => "1",
                :hour => "1"
            )
        }

        return cron
    end

    # Run the cron through its paces -- install it then remove it.
    def cyclecron(cron)
        name = cron.name
        comp = newcomp(name, cron)

        trans = assert_events([:cron_created], comp)
        cron.retrieve
        assert(cron.insync?)
        trans = assert_events([], comp)
        cron[:command] = :notfound
        trans = assert_events([:cron_deleted], comp)
        # the cron should no longer exist, not even in the comp
        trans = assert_events([], comp)

        assert(!comp.include?(cron),
            "Cron is still a member of comp, after being deleted")
    end

    # A simple test to see if we can load the cron from disk.
    def test_load
        assert_nothing_raised {
            @crontype.retrieve(@me)
        }
    end

    # Test that a cron job turns out as expected, by creating one and generating
    # it directly
    def test_simple_to_cron
        cron = nil
        # make the cron
        name = "yaytest"
        assert_nothing_raised {
            cron = @crontype.create(
                :name => name,
                :command => "date > /dev/null",
                :user => @me
            )
        }
        str = nil
        # generate the text
        assert_nothing_raised {
            str = cron.to_cron
        }

        assert_equal(str, "# Puppet Name: #{name}\n* * * * * date > /dev/null",
            "Cron did not generate correctly")
    end

    # Test that changing any field results in the cron tab being rewritten.
    # it directly
    def test_any_field_changes
        cron = nil
        # make the cron
        name = "yaytest"
        assert_nothing_raised {
            cron = @crontype.create(
                :name => name,
                :command => "date > /dev/null",
                :month => "May",
                :user => @me
            )
        }
        comp = newcomp(cron)
        assert_events([:cron_created], comp)

        assert_nothing_raised {
            cron[:month] = "June"
        }

        assert_events([:cron_changed], comp)
    end

    # Test that a cron job with spaces at the end doesn't get rewritten
    def test_trailingspaces
        cron = nil
        # make the cron
        name = "yaytest"
        assert_nothing_raised {
            cron = @crontype.create(
                :name => name,
                :command => "date > /dev/null ",
                :month => "May",
                :user => @me
            )
        }
        comp = newcomp(cron)

        assert_events([:cron_created], comp, "did not create cron job")
        assert_events([], comp, "cron job got rewritten")
    end
    
    # Test that comments are correctly retained
    def test_retain_comments
        str = "# this is a comment\n#and another comment\n"
        user = "fakeuser"
        assert_nothing_raised {
            @crontype.parse(user, str)
        }

        assert_nothing_raised {
            newstr = @crontype.tab(user)
            assert_equal(str, newstr, "Cron comments were changed or lost")
        }
    end

    # Test that a specified cron job will be matched against an existing job
    # with no name, as long as all fields match
    def test_matchcron
        str = "0,30 * * * * date\n"

        assert_nothing_raised {
            @crontype.parse(@me, str)
        }

        assert_nothing_raised {
            cron = @crontype.create(
                :name => "yaycron",
                :minute => [0, 30],
                :command => "date",
                :user => @me
            )
        }

        modstr = "# Puppet Name: yaycron\n%s" % str

        assert_nothing_raised {
            newstr = @crontype.tab(@me)
            assert_equal(modstr, newstr, "Cron was not correctly matched")
        }
    end

    # Test adding a cron when there is currently no file.
    def test_mkcronwithnotab
        Puppet.type(:cron).crontype.remove(@me)

        cron = mkcron("testwithnotab")
        cyclecron(cron)
    end

    def test_mkcronwithtab
        Puppet.type(:cron).crontype.remove(@me)
        Puppet.type(:cron).crontype.write(@me,
"1 1 1 1 * date > %s/crontesting\n" % tstdir()
        )

        cron = mkcron("testwithtab")
        cyclecron(cron)
    end

    def test_makeandretrievecron
        Puppet.type(:cron).crontype.remove(@me)

        name = "storeandretrieve"
        cron = mkcron(name)
        comp = newcomp(name, cron)
        trans = assert_events([:cron_created], comp, name)
        
        cron = nil

        Puppet.type(:cron).clear
        Puppet.type(:cron).retrieve(@me)

        assert(cron = Puppet.type(:cron)[name], "Could not retrieve named cron")
        assert_instance_of(Puppet.type(:cron), cron)
    end

    # Do input validation testing on all of the parameters.
    def test_arguments
        values = {
            :monthday => {
                :valid => [ 1, 13, "1" ],
                :invalid => [ -1, 0, 32 ]
            },
            :weekday => {
                :valid => [ 0, 3, 6, "1", "tue", "wed",
                    "Wed", "MOnday", "SaTurday" ],
                :invalid => [ -1, 7, "13", "tues", "teusday", "thurs" ]
            },
            :hour => {
                :valid => [ 0, 21, 23 ],
                :invalid => [ -1, 24 ]
            },
            :minute => {
                :valid => [ 0, 34, 59 ],
                :invalid => [ -1, 60 ]
            },
            :month => {
                :valid => [ 1, 11, 12, "mar", "March", "apr", "October", "DeCeMbEr" ],
                :invalid => [ -1, 0, 13, "marc", "sept" ]
            }
        }

        cron = mkcron("valtesting")
        values.each { |param, hash|
            # We have to test the valid ones first, because otherwise the
            # state will fail to create at all.
            [:valid, :invalid].each { |type|
                hash[type].each { |value|
                    case type
                    when :valid:
                        assert_nothing_raised {
                            cron[param] = value
                        }

                        if value.is_a?(Integer)
                            assert_equal(value.to_s, cron.should(param),
                                "Cron value was not set correctly")
                        end
                    when :invalid:
                        assert_raise(Puppet::Error, "%s is incorrectly a valid %s" %
                            [value, param]) {
                            cron[param] = value
                        }
                    end

                    if value.is_a?(Integer)
                        value = value.to_s
                        redo
                    end
                }
            }
        }
    end
end

# $Id$