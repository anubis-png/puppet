require 'autotest'
require 'autotest/rspec'

class Autotest::PuppetRspec < Autotest::Rspec
  def initialize # :nodoc:
    super
    @test_mappings = {
        # the libraries under lib/puppet
        %r%^lib/puppet/(.*)\.rb$% => proc { |filename, m|
          files_matching %r!spec/(unit|integration)/#{m[1]}.rb!
        },

	# the actual spec files themselves
        %r%^spec/(unit|integration)/.*\.rb$% => proc { |filename, _|
          filename
        },

    # force a complete re-run for all of these:

	# main puppet lib
	%r!^lib/puppet\.rb$! => proc { |filename, _|
          files_matching %r!spec/(unit|integration)/.*\.rb!
	},

	# the spec_helper
	%r!^spec/spec_helper\.rb$! => proc { |filename, _|
          files_matching %r!spec/(unit|integration)/.*\.rb!
	},

	# the puppet test libraries
	%r!^test/lib/puppettest/.*! => proc { |filename, _|
          files_matching %r!spec/(unit|integration)/.*\.rb!
	},

        # the puppet spec libraries
	%r!^spec/lib/spec.*! => proc { |filename, _|
          files_matching %r!spec/(unit|integration)/.*\.rb!
	},

        # the monkey patches for rspec
	%r!^spec/lib/monkey_patches/.*! => proc { |filename, _|
          files_matching %r!spec/(unit|integration)/.*\.rb!
	},
    }
  end

  # Autotest will look for spec commands in the following
  # locations, in this order:
  #
  #   * bin/spec
  #   * default spec bin/loader installed in Rubygems
  #   * our local vendor/gems/rspec/bin/spec
  def spec_commands
    [
      File.join('bin', 'spec'),
      File.join(Config::CONFIG['bindir'], 'spec'),
      File.join('vendor', 'gems', 'rspec', 'bin', 'spec') 
    ]
  end

end