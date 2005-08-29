if __FILE__ == $0
    $:.unshift '..'
    $:.unshift '../../lib'
    $:.unshift "../../../../language/trunk/lib"
    $puppetbase = "../../../../language/trunk"
end

require 'puppet'
require 'cgi'
require 'test/unit'
require 'fileutils'
require 'puppettest'

# $Id$

class TestFileSources < Test::Unit::TestCase
    include FileTesting
    # hmmm
    # this is complicated, because we store references to the created
    # objects in a central store
    def mkfile(hash)
        file = nil
        assert_nothing_raised {
            file = Puppet::Type::PFile.new(hash)
        }
        return file
    end

    def mktestfile
        # because luke's home directory is on nfs, it can't be used for testing
        # as root
        tmpfile = tempfile()
        File.open(tmpfile, "w") { |f| f.puts rand(100) }
        @@tmpfiles.push tmpfile
        mkfile(:name => tmpfile)
    end

    def setup
        @@tmpfiles = []
        @@tmppids = []
        Puppet[:loglevel] = :debug if __FILE__ == $0
        Puppet[:checksumfile] = File.join(Puppet[:statedir], "checksumtestfile")
        begin
            initstorage
        rescue
            system("rm -rf %s" % Puppet[:checksumfile])
        end
    end

    def teardown
        clearstorage
        Puppet::Type.allclear
        @@tmppids.each { |pid|
            system("kill -INT %s" % pid)
        }
        @@tmpfiles.each { |file|
            if FileTest.exists?(file)
                system("chmod -R 755 %s" % file)
                system("rm -rf %s" % file)
            end
        }
        @@tmpfiles.clear
        system("rm -f %s" % Puppet[:checksumfile])
    end

    def initstorage
        Puppet::Storage.init
        Puppet::Storage.load
    end

    def clearstorage
        Puppet::Storage.store
        Puppet::Storage.clear
    end

    def test_newchild
        path = "/tmp/newchilddir"
        @@tmpfiles.push path

        system("mkdir -p #{path}")
        File.open(File.join(path,"childtest"), "w") { |of|
            of.puts "yayness"
        }
        file = nil
        comp = nil
        trans = nil
        assert_nothing_raised {
            file = Puppet::Type::PFile.new(
                :name => path
            )
        }
        child = nil
        assert_nothing_raised {
            child = file.newchild("childtest")
        }
        assert(child)
        assert_nothing_raised {
            child = file.newchild("childtest")
        }
        assert(child)
        assert_raise(Puppet::DevError) {
            file.newchild(File.join(path,"childtest"))
        }
    end

    def test_simplelocalsource
        path = "/tmp/Filesourcetest"
        @@tmpfiles.push path
        system("mkdir -p #{path}")
        frompath = File.join(path,"source")
        topath = File.join(path,"dest")
        fromfile = nil
        tofile = nil
        trans = nil

        File.open(frompath, File::WRONLY|File::CREAT|File::APPEND) { |of|
            of.puts "yayness"
        }
        assert_nothing_raised {
            tofile = Puppet::Type::PFile.new(
                :name => topath,
                :source => frompath
            )
        }
        comp = Puppet::Type::Component.new(
            :name => "component"
        )
        comp.push tofile
        assert_nothing_raised {
            trans = comp.evaluate
        }
        assert_nothing_raised {
            trans.evaluate
        }
        assert_nothing_raised {
            comp.sync
        }
        assert(FileTest.exists?(topath))
        from = File.open(frompath) { |o| o.read }
        to = File.open(topath) { |o| o.read }
        assert_equal(from,to)
        clearstorage
        Puppet::Type.allclear
        @@tmpfiles.push path
    end

    def recursive_source_test(fromdir, todir)
        initstorage
        tofile = nil
        trans = nil

        assert_nothing_raised {
            tofile = Puppet::Type::PFile.new(
                :name => todir,
                "recurse" => true,
                "backup" => false,
                "source" => fromdir
            )
        }
        comp = Puppet::Type::Component.new(
            :name => "component"
        )
        comp.push tofile
        assert_nothing_raised {
            trans = comp.evaluate
        }
        assert_nothing_raised {
            trans.evaluate
        }

        assert(FileTest.exists?(todir))

        clearstorage
        Puppet::Type.allclear
    end

    def run_complex_sources(networked = false)
        path = "/tmp/ComplexSourcesTest"
        @@tmpfiles.push path

        # first create the source directory
        system("mkdir -p #{path}")


        # okay, let's create a directory structure
        fromdir = File.join(path,"fromdir")
        Dir.mkdir(fromdir)
        FileUtils.cd(fromdir) {
            mkranddirsandfiles()
        }

        todir = File.join(path, "todir")
        source = fromdir
        if networked
            source = "puppet://localhost/%s%s" % [networked, fromdir]
        end
        recursive_source_test(source, todir)

        return [fromdir,todir]
    end

    def test_complex_sources_twice
        fromdir, todir = run_complex_sources
        assert_trees_equal(fromdir,todir)
        recursive_source_test(fromdir, todir)
        assert_trees_equal(fromdir,todir)
    end

    def test_sources_with_deleted_destfiles
        fromdir, todir = run_complex_sources
        # then delete some files
        assert(FileTest.exists?(todir))
        delete_random_files(todir)

        # and run
        recursive_source_test(fromdir, todir)

        # and make sure they're still equal
        assert_trees_equal(fromdir,todir)
    end

    def test_sources_with_readonly_destfiles
        fromdir, todir = run_complex_sources
        assert(FileTest.exists?(todir))
        readonly_random_files(todir)
        recursive_source_test(fromdir, todir)

        # and make sure they're still equal
        assert_trees_equal(fromdir,todir)
    end

    def test_sources_with_modified_dest_files
        fromdir, todir = run_complex_sources

        assert(FileTest.exists?(todir))
        # then modify some files
        modify_random_files(todir)

        recursive_source_test(fromdir, todir)

        # and make sure they're still equal
        assert_trees_equal(fromdir,todir)
    end

    def test_sources_with_added_destfiles
        fromdir, todir = run_complex_sources
        assert(FileTest.exists?(todir))
        # and finally, add some new files
        add_random_files(todir)

        recursive_source_test(fromdir, todir)

        fromtree = file_list(fromdir)
        totree = file_list(todir)

        assert(fromtree != totree)

        # then remove our new files
        FileUtils.cd(todir) {
            %x{find . 2>/dev/null}.chomp.split(/\n/).each { |file|
                if file =~ /file[0-9]+/
                    File.unlink(file)
                end
            }
        }

        # and make sure they're still equal
        assert_trees_equal(fromdir,todir)
    end

    def test_RecursionWithAddedFiles
        basedir = "/tmp/recursionplussaddedfiles"
        Dir.mkdir(basedir)
        @@tmpfiles << basedir
        file1 = File.join(basedir, "file1")
        file2 = File.join(basedir, "file2")
        subdir1 = File.join(basedir, "subdir1")
        file3 = File.join(subdir1, "file")
        File.open(file1, "w") { |f| 3.times { f.print rand(100) } }
        rootobj = nil
        assert_nothing_raised {
            rootobj = Puppet::Type::PFile.new(
                :name => basedir,
                :recurse => true,
                :check => %w{type owner}
            )

            rootobj.evaluate
        }

        klass = Puppet::Type::PFile
        assert(klass[basedir])
        assert(klass[file1])
        assert_nil(klass[file2])

        File.open(file2, "w") { |f| 3.times { f.print rand(100) } }

        assert_nothing_raised {
            rootobj.evaluate
        }
        assert(klass[file2])

        Dir.mkdir(subdir1)
        File.open(file3, "w") { |f| 3.times { f.print rand(100) } }

        assert_nothing_raised {
            rootobj.evaluate
        }
        assert(klass[file3])
    end

    def mkfileserverconf(mounts)
        file = "/tmp/fileserverconftestingfile%s" % rand(100)
        File.open(file, "w") { |f|
            mounts.each { |path, name|
                f.puts "[#{name}]\n\tpath #{path}\n\tallow *\n"
            }
        }

        @@tmpfiles << file
        return file
    end

    def test_zSimpleNetworkSources
        server = nil
        basedir = "/tmp/simplnetworksourcetesting"

        mounts = {
            "/" => "root"
        }

        fileserverconf = mkfileserverconf(mounts)

        if File.exists?(basedir)
            system("rm -rf %s" % basedir)
        end
        Dir.mkdir(basedir)

        Puppet[:puppetconf] = basedir
        Puppet[:puppetvar] = basedir
        Puppet[:autosign] = true
        @@tmpfiles << basedir

        tmpname = "yaytesting"
        tmpfile = File.join(basedir, tmpname)
        File.open(tmpfile, "w") { |f| f.print rand(100) }

        port = 8765
        serverpid = nil
        assert_nothing_raised() {
            server = Puppet::Server.new(
                :Port => port,
                :Handlers => {
                    :CA => {}, # so that certs autogenerate
                    :FileServer => {
                        :Config => fileserverconf
                    }
                }
            )

        }
        serverpid = fork {
            assert_nothing_raised() {
                #trap(:INT) { server.shutdown; Kernel.exit! }
                trap(:INT) { server.shutdown }
                server.start
            }
        }
        @@tmppids << serverpid

        client = nil
        assert_nothing_raised() {
            client = XMLRPC::Client.new("localhost", "/RPC2", port, nil, nil,
                nil, nil, true, 3)
        }
        retval = nil

        sleep(1)

        list = nil
        rpath = "/root%s" % tmpfile
        assert_nothing_raised {
            list = client.call("fileserver.list", rpath, false)
        }

        assert_equal("/\tfile", list)

        assert_nothing_raised {
            list = client.call("fileserver.describe", rpath)
        }

        assert_match(/^\d+\tfile\t\d+\t\d+\t.+$/, list)

        assert_nothing_raised {
            list = client.call("fileserver.retrieve", rpath)
        }

        contents = File.read(tmpfile)
        assert_equal(contents, CGI.unescape(list))

        assert_nothing_raised {
            system("kill -INT %s" % serverpid)
        }
    end

    def test_zNetworkSources
        server = nil
        basedir = "/tmp/networksourcetesting"
        if File.exists?(basedir)
            system("rm -rf %s" % basedir)
        end
        Dir.mkdir(basedir)

        mounts = {
            "/" => "root"
        }

        fileserverconf = mkfileserverconf(mounts)

        Puppet[:puppetconf] = basedir
        Puppet[:puppetvar] = basedir
        Puppet[:autosign] = true
        @@tmpfiles << basedir

        Puppet[:masterport] = 8762

        serverpid = nil
        assert_nothing_raised() {
            server = Puppet::Server.new(
                :Handlers => {
                    :CA => {}, # so that certs autogenerate
                    :FileServer => {
                        :Config => fileserverconf
                    }
                }
            )

        }
        serverpid = fork {
            assert_nothing_raised() {
                #trap(:INT) { server.shutdown; Kernel.exit! }
                trap(:INT) { server.shutdown }
                server.start
            }
        }
        @@tmppids << serverpid

        sleep(1)

        fromdir, todir = run_complex_sources("root")
        assert_trees_equal(fromdir,todir)
        recursive_source_test(fromdir, todir)
        assert_trees_equal(fromdir,todir)

        assert_nothing_raised {
            system("kill -INT %s" % serverpid)
        }
    end
end