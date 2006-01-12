if __FILE__ == $0
    $:.unshift '..'
    $:.unshift '../../lib'
    $puppetbase = ".."
end

require 'puppet'
require 'puppet/config'
require 'puppettest'
require 'test/unit'

class TestConfFiles < Test::Unit::TestCase
    include TestPuppet

    @@gooddata = [
        {
            "fun" => {
                "a" => "b",
                "c" => "d",
                "e" => "f"
            },
            "yay" => {
                "aa" => "bk",
                "ca" => "dk",
                "ea" => "fk"
            },
            "boo" => {
                "eb" => "fb"
            },
            "rah" => {
                "aa" => "this is a sentence",
                "ca" => "dk",
                "ea" => "fk"
            },
        },
        {
            "puppet" => {
                "yay" => "rah"
            },
            "booh" => {
                "okay" => "rah"
            },
            "back" => {
                "okay" => "rah"
            },
        }
    ]

    def data2config(data)
        str = ""

        if data.include?("puppet")
            # because we're modifying it
            data = data.dup
            str += "[puppet]\n"
            data["puppet"].each { |var, value|
                str += "%s %s\n" % [var, value]
            }
            data.delete("puppet")
        end

        data.each { |type, settings|
            str += "[%s]\n" % type
            settings.each { |var, value|
                str += "%s %s\n" % [var, value]
            }
        }

        return str
    end

    def sampledata
        if block_given?
            @@gooddata.each { |hash| yield hash }
        else
            return @@gooddata[0]
        end
    end

    def test_readconfig
        path = tempfile()

        sampledata { |data|
            # Write it out as a config file
            File.open(path, "w") { |f| f.print data2config(data) }
            config = nil
            assert_nothing_raised {
                config = Puppet::Config.new(path)
            }

            data.each { |section, hash|
                hash.each { |var, value|
                    assert_equal(
                        data[section][var],
                        config[section][var],
                        "Got different values at %s/%s" % [section, var]
                    )
                }
            }
        }
    end
end

# $Id$