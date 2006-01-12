if __FILE__ == $0
    $:.unshift '..'
    $:.unshift '../../lib'
    $puppetbase = "../../../../language/trunk"
end

require 'puppet'
require 'puppettest'
require 'test/unit'

# $Id$

class TestSymlink < Test::Unit::TestCase
	include FileTesting
    def mktmpfile
        # because luke's home directory is on nfs, it can't be used for testing
        # as root
        tmpfile = tempfile()
        File.open(tmpfile, "w") { |f| f.puts rand(100) }
        @@tmpfiles.push tmpfile
        return tmpfile
    end

    def mktmpdir
        dir = File.join(tmpdir(), "puppetlinkdir")
        unless FileTest.exists?(dir)
            Dir.mkdir(dir)
        end
        @@tmpfiles.push dir
        return dir
    end

    def tmplink
        link = File.join(tmpdir(), "puppetlinktest")
        @@tmpfiles.push link
        return link
    end

    def newlink(hash = {})
        hash[:name] = tmplink()
        unless hash.include?(:target)
            hash[:target] = mktmpfile()
        end
        link = Puppet.type(:symlink).create(hash)
        return link
    end

    def test_target
        link = nil
        file = mktmpfile()
        assert_nothing_raised() {
            link = newlink()
        }
        assert_nothing_raised() {
            link.retrieve
        }
        # we might already be in sync
        assert(!link.insync?())
        assert_apply(link)
        assert_nothing_raised() {
            link.retrieve
        }
        assert(link.insync?())
    end

    def test_recursion
        source = mktmpdir()
        FileUtils.cd(source) {
            mkranddirsandfiles()
        }

        link = nil
        assert_nothing_raised {
            link = newlink(:target => source, :recurse => true)
        }
        comp = newcomp("linktest",link)
        cycle(comp)

        path = link.name
        list = file_list(path)
        FileUtils.cd(path) {
            list.each { |file|
                unless FileTest.directory?(file)
                    assert(FileTest.symlink?(file))
                    target = File.readlink(file)
                    assert_equal(target,File.join(source,file.sub(/^\.\//,'')))
                end
            }
        }
    end
end