module Puppet
    module PackagingType
        # The packaging system for Debian systems.
        module DPKG
            def query
                packages = []

                # dpkg only prints as many columns as you have available
                # which means we don't get all of the info
                # stupid stupid
                oldcol = ENV["COLUMNS"]
                ENV["COLUMNS"] = "500"
                fields = [:desired, :status, :error, :name, :version, :description]

                hash = {}
                # list out our specific package
                open("| dpkg -l %s 2>/dev/null" % self.name) { |process|
                    # our regex for matching dpkg output
                    regex = %r{^(.)(.)(.)\s(\S+)\s+(\S+)\s+(.+)$}

                    # we only want the last line
                    lines = process.readlines
                    # we've got four header lines, so we should expect all of those
                    # plus our output
                    if lines.length < 5
                        return nil
                    end

                    line = lines[-1]

                    if match = regex.match(line)
                        fields.zip(match.captures) { |field,value|
                            hash[field] = value
                        }
                        #packages.push Puppet::Type::Package.installedpkg(hash)
                    else
                        raise Puppet::DevError,
                            "failed to match dpkg line %s" % line
                    end
                }
                ENV["COLUMNS"] = oldcol

                if hash[:error] != " "
                    raise Puppet::PackageError.new(
                        "Package %s, version %s is in error state: %s" %
                            [hash[:name], hash[:install], hash[:error]]
                    )
                end

                if hash[:status] == "i"
                    hash[:install] = hash[:version]
                else
                    hash[:install] = :notinstalled
                end

                return hash
            end

            def list
                packages = []

                # dpkg only prints as many columns as you have available
                # which means we don't get all of the info
                # stupid stupid
                oldcol = ENV["COLUMNS"]
                ENV["COLUMNS"] = "500"

                # list out all of the packages
                open("| dpkg -l") { |process|
                    # our regex for matching dpkg output
                    regex = %r{^(\S+)\s+(\S+)\s+(\S+)\s+(.+)$}
                    fields = [:status, :name, :install, :description]
                    hash = {}

                    5.times { process.gets } # throw away the header

                    # now turn each returned line into a package object
                    process.each { |line|
                        if match = regex.match(line)
                            hash.clear

                            fields.zip(match.captures) { |field,value|
                                hash[field] = value
                            }
                            packages.push Puppet::Type::Package.installedpkg(hash)
                        else
                            raise Puppet::DevError,
                                "Failed to match dpkg line %s" % line
                        end
                    }
                }
                ENV["COLUMNS"] = oldcol

                return packages
            end

            def remove
                cmd = "dpkg -r %s" % self.name
                output = %x{#{cmd} 2>&1}
                if $? != 0
                    raise Puppet::PackageError.new(output)
                end
            end
        end
    end
end

# $Id$