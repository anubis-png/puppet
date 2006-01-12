if __FILE__ == $0
    $:.unshift '..'
    $:.unshift '../../lib'
    $puppetbase = "../.."
end

require 'puppet'
require 'puppettest'
require 'test/unit'

# $Id$

class TestTransactions < Test::Unit::TestCase
	include FileTesting
    def ingroup(gid)
        require 'etc'
        begin
            group = Etc.getgrgid(gid)
        rescue => detail
            puts "Could not retrieve info for group %s: %s" % [gid, detail]
            return nil
        end

        return @groups.include?(group.name)
    end

    def setup
        super
        @groups = %x{groups}.chomp.split(/ /)
        unless @groups.length > 1
            p @groups
            raise "You must be a member of more than one group to test this"
        end
    end

    def teardown
        stopservices
        #print "\n\n" if Puppet[:debug]
        super
    end

    def newfile(hash = {})
        tmpfile = tempfile()
        File.open(tmpfile, "w") { |f| f.puts rand(100) }

        # XXX now, because os x apparently somehow allows me to make a file
        # owned by a group i'm not a member of, i have to verify that
        # the file i just created is owned by one of my groups
        # grrr
        unless ingroup(File.stat(tmpfile).gid)
            Puppet.info "Somehow created file in non-member group %s; fixing" %
                File.stat(tmpfile).gid

            require 'etc'
            firstgr = @groups[0]
            unless firstgr.is_a?(Integer)
                str = Etc.getgrnam(firstgr)
                firstgr = str.gid
            end
            File.chown(nil, firstgr, tmpfile)
        end

        @@tmpfiles.push tmpfile
        hash[:name] = tmpfile
        assert_nothing_raised() {
            return Puppet.type(:file).create(hash)
        }
    end

    def newservice
        assert_nothing_raised() {
            return Puppet.type(:service).create(
                :name => "sleeper",
                :type => "init",
                :path => File.join($puppetbase,"examples/root/etc/init.d"),
                :hasstatus => true,
                :check => [:running]
            )
        }
    end

    def newexec(file)
        assert_nothing_raised() {
            return Puppet.type(:exec).create(
                :name => "touch %s" % file,
                :path => "/bin:/usr/bin:/sbin:/usr/sbin",
                :returns => 0
            )
        }
    end

    # modify a file and then roll the modifications back
    def test_filerollback
        transaction = nil
        file = newfile()

        states = {}
        check = [:group,:mode]
        file[:check] = check

        assert_nothing_raised() {
            file.retrieve
        }

        assert_nothing_raised() {
            check.each { |state|
                assert(file[state])
                states[state] = file[state]
            }
        }


        component = newcomp("file",file)
        require 'etc'
        groupname = Etc.getgrgid(File.stat(file.name).gid).name
        assert_nothing_raised() {
            # Find a group that it's not set to
            group = @groups.find { |group| group != groupname }
            unless group
                raise "Could not find suitable group"
            end
            file[:group] = group

            file[:mode] = "755"
        }
        trans = assert_events([:inode_changed, :inode_changed], component)

        assert_rollback_events(trans, [:inode_changed, :inode_changed], "file")

        assert_nothing_raised() {
            file.retrieve
        }
        states.each { |state,value|
            assert_equal(
                value,file.is(state), "File %s remained %s" % [state, file.is(state)]
            )
        }
    end

    # start a service, and then roll the modification back
    # Disabled, because it wasn't really worth the effort.
    def disabled_test_servicetrans
        transaction = nil
        service = newservice()

        component = newcomp("service",service)

        assert_nothing_raised() {
            service[:running] = 1
        }
        service.retrieve
        assert(service.insync?, "Service did not start")
        system("ps -ef | grep ruby")
        trans = assert_events([:service_started], component)
        service.retrieve

        assert_rollback_events(trans, [:service_stopped], "service")
    end

    # test that services are correctly restarted and that work is done
    # in the right order
    def test_refreshing
        transaction = nil
        file = newfile()
        execfile = File.join(tmpdir(), "exectestingness")
        exec = newexec(execfile)
        states = {}
        check = [:group,:mode]
        file[:check] = check

        @@tmpfiles << execfile

        component = newcomp("both",file,exec)

        # 'subscribe' expects an array of arrays
        exec[:subscribe] = [[file.class.name,file.name]]
        exec[:refreshonly] = true

        assert_nothing_raised() {
            file.retrieve
            exec.retrieve
        }

        check.each { |state|
            states[state] = file[state]
        }
        assert_nothing_raised() {
            file[:mode] = "755"
        }

        trans = assert_events( [:inode_changed], component)

        assert(FileTest.exists?(execfile), "Execfile does not exist")
        File.unlink(execfile)
        assert_nothing_raised() {
            file[:group] = @groups[1]
        }

        trans = assert_events([:inode_changed], component)
        assert(FileTest.exists?(execfile), "Execfile does not exist")
    end

    def test_zrefreshAcrossTwoComponents
        transaction = nil
        file = newfile()
        execfile = File.join(tmpdir(), "exectestingness2")
        @@tmpfiles << execfile
        exec = newexec(execfile)
        states = {}
        check = [:group,:mode]
        file[:check] = check

        fcomp = newcomp("file",file)
        ecomp = newcomp("exec",exec)

        component = newcomp("both",fcomp,ecomp)

        # 'subscribe' expects an array of arrays
        #component[:require] = [[file.class.name,file.name]]
        ecomp[:subscribe] = [[fcomp.class.name,fcomp.name]]
        exec[:refreshonly] = true

        trans = assert_events([], component)

        assert_nothing_raised() {
            file[:group] = @groups[1]
            file[:mode] = "755"
        }

        trans = assert_events([:inode_changed, :inode_changed], component)

    end

end