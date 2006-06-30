module Puppet
class Server
    # A simple server for triggering a new run on a Puppet client.
    class Report < Handler
        @interface = XMLRPC::Service::Interface.new("puppetreports") { |iface|
            iface.add_method("string report(array)")
        }

        Puppet.setdefaults(:reporting,
            :reportdirectory => {:default => "$vardir/reports",
                    :mode => 0750,
                    :owner => "$user",
                    :group => "$group",
                    :desc => "The directory in which to store reports received from the
                client.  Each client gets a separate subdirectory."},
            :reports => ["none",
                "The list of reports to generate.  All reports are looked for
                in puppet/reports/<name>.rb, and multiple report names should be
                comma-separated (whitespace is okay)."
            ]
        )

        @hooks = {}

        class << self
            attr_reader :hooks
        end

        # Add a hook for processing reports.
        def self.newreport(name, &block)
            name = name.intern if name.is_a? String
            @hooks[name] = block
        end

        def self.report(name)
            name = name.intern if name.is_a? String
            unless @hooks.include? name
                begin
                    require "puppet/reports/#{name}"
                    unless @hooks.include? name
                        Puppet.warning(
                            "Loaded report file for %s but report was not defined" %
                            name
                        )
                        return nil
                    end
                rescue LoadError => detail
                    if Puppet[:debug]
                        puts detail.backtrace
                    end
                    Puppet.warning "Could not load report %s: %s" %
                        [name, detail]
                    next
                end
            end

            @hooks[name]
        end

        def initialize(*args)
            super
            Puppet.config.use(:reporting)
        end

        def mkclientdir(client, dir)
            Puppet.config.setdefaults("reportclient-#{client}",
                :clientdir => { :default => dir,
                    :mode => 0750,
                    :owner => "$user",
                    :group => "$group"
                }
            )

            Puppet.config.use("reportclient-#{client}")
        end

        # Accept a report from a client.
        def report(report, client = nil, clientip = nil)
            # We need the client name for storing files.
            client ||= Facter["hostname"].value

            # Unescape the report
            unless @local
                report = CGI.unescape(report)
            end

            process(report)

            # We don't want any tracking back in the fs.  Unlikely, but there
            # you go.
            client.gsub("..",".")

            dir = File.join(Puppet[:reportdirectory], client)

            unless FileTest.exists?(dir)
                mkclientdir(client, dir)
            end

            # Now store the report.
            now = Time.now.gmtime
            name = %w{year month day hour min}.collect do |method|
                # Make sure we're at least two digits everywhere
                "%02d" % now.send(method).to_s
            end.join("") + ".yaml"

            file = File.join(dir, name)

            begin
                File.open(file, "w", 0640) do |f|
                    f.puts report
                end
            rescue => detail
                if Puppet[:debug]
                    puts detail.backtrace
                end
                Puppet.warning "Could not write report for %s at %s: %s" %
                    [client, file, detail]
            end


            # Our report is in YAML
            return file
        end

        private

        # Process the report using all of the existing hooks.
        def process(report)
            return if Puppet[:reports] == "none"

            # First convert the report to real objects
            begin
                report = YAML.load(report)
            rescue => detail
                Puppet.warning "Could not load report: %s" % detail
                return
            end

            Puppet[:reports].split(/\s*,\s*/).each do |name|
                next unless hook = self.class.report(name)

                Puppet.info "Processing report %s" % name

                begin
                    hook.call(report)
                rescue => detail
                    if Puppet[:debug]
                        puts detail.backtrace
                    end
                    Puppet.err "Report %s failed: %s" %
                        [name, detail]
                end
            end
        end
    end
end
end

# $Id$