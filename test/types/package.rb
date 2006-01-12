if __FILE__ == $0
    $:.unshift '..'
    $:.unshift '../../lib'
    $puppetbase = "../.."
end

require 'puppettest'
require 'puppet'
require 'test/unit'
require 'facter'

$platform = Facter["operatingsystem"].value

unless Puppet.type(:package).default
    puts "No default package type for %s; skipping package tests" % $platform
else

class TestPackageSource < Test::Unit::TestCase
	include TestPuppet
    def test_filesource
        path = tempfile()
        system("touch %s" % path)
        assert_equal(
            path,
            Puppet::PackageSource.get("file://#{path}")
        )
    end
end

class TestPackages < Test::Unit::TestCase
	include FileTesting
    def setup
        super
        #@list = Puppet.type(:package).getpkglist
        Puppet.type(:package).clear
    end

    # These are packages that we're sure will be installed
    def installedpkgs
        pkgs = nil
        case $platform
        when "SunOS"
            pkgs = %w{SMCossh}
        when "Debian": pkgs = %w{ssh openssl}
        when "Fedora": pkgs = %w{openssh}
        else
            Puppet.notice "No test package for %s" % $platform
            return []
        end

        return pkgs
    end

    def mkpkgs
        tstpkgs().each { |pkg|
            if pkg.is_a?(Array)
                hash = {:name => pkg[0], :source => pkg[1]}
                hash[:install] = "true"

                unless File.exists?(hash[:source])
                    Puppet.info "No package file %s for %s; skipping some package tests" %
                        [hash[:source], Facter["operatingsystem"].value]
                end
                yield Puppet.type(:package).create(hash)
            else
                yield Puppet.type(:package).create(
                    :name => pkg, :install => "latest"
                )
            end
        }
    end

    def tstpkgs
        retval = []
        case $platform
        when "Solaris":
            arch = Facter["hardwareisa"].value + Facter["operatingsystemrelease"].value
            case arch
            when "sparc5.8":
                retval = [["SMCarc", "/usr/local/pkg/arc-5.21e-sol8-sparc-local"]]
            when "i3865.8":
                retval = [["SMCarc", "/usr/local/pkg/arc-5.21e-sol8-intel-local"]]
            end
        when "Debian":
            retval = %w{zec}
        #when "RedHat": type = :rpm
        when "Fedora":
            retval = %w{wv}
        else
            Puppet.notice "No test packages for %s" % $platform
        end

        return retval
    end

    def mkpkgcomp(pkg)
        assert_nothing_raised {
            pkg = Puppet.type(:package).create(:name => pkg, :install => true)
        }
        assert_nothing_raised {
            pkg.retrieve
        }

        comp = newcomp("package", pkg)

        return comp
    end

    def test_retrievepkg
        installedpkgs().each { |pkg|
            obj = nil
            assert_nothing_raised {
                obj = Puppet.type(:package).create(
                    :name => pkg
                )
            }

            assert(obj, "could not create package")

            assert_nothing_raised {
                obj.retrieve
            }

            assert(obj.is(:install), "Could not retrieve package version")
        }
    end

    def test_nosuchpkg
        obj = nil
        assert_nothing_raised {
            obj = Puppet.type(:package).create(
                :name => "thispackagedoesnotexist"
            )
        }

        assert_nothing_raised {
            obj.retrieve
        }

        assert_equal(:notinstalled, obj.is(:install),
            "Somehow retrieved unknown pkg's version")
    end

    def test_latestpkg
        tstpkgs { |pkg|
            assert_nothing_raised {
                assert(pkg.latest, "Package did not return value for 'latest'")
            }
        }
    end

    unless Process.uid == 0
        $stderr.puts "Run as root to perform package installation tests"
    else
    def test_installpkg
        mkpkgs { |pkg|
            # we first set install to 'true', and make sure something gets
            # installed
            assert_nothing_raised {
                pkg.retrieve
            }

            if pkg.insync?
                Puppet.notice "Test package %s is already installed; please choose a different package for testing" % pkg
                next
            end

            comp = newcomp("package", pkg)

            assert_events([:package_installed], comp, "package")

            # then uninstall it
            assert_nothing_raised {
                pkg[:install] = false
            }


            pkg.retrieve

            assert(! pkg.insync?, "Package is in sync")

            assert_events([:package_removed], comp, "package")

            # and now set install to 'latest' and verify it installs
            # FIXME this isn't really a very good test -- we should install
            # a low version, and then upgrade using this.  But, eh.
            if pkg.respond_to?(:latest)
                assert_nothing_raised {
                    pkg[:install] = "latest"
                }

                assert_events([:package_installed], comp, "package")

                pkg.retrieve
                assert(pkg.insync?, "After install, package is not insync")

                assert_nothing_raised {
                    pkg[:install] = false
                }

                pkg.retrieve

                assert(! pkg.insync?, "Package is insync")

                assert_events([:package_removed], comp, "package")
            end
        }
    end
    end
end
end

# $Id$