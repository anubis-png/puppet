#!/usr/local/bin/ruby -w

# $Id$

# the server
#
# allow things to connect to us and communicate, and stuff

require 'puppet'
require 'puppet/daemon'

$noservernetworking = false

begin
    require 'webrick'
    require 'webrick/https'
    require 'cgi'
    require 'xmlrpc/server'
    require 'xmlrpc/client'
rescue LoadError => detail
    $noservernetworking = detail
end

module Puppet
    class ServerError < RuntimeError; end
    #---------------------------------------------------------------
    if $noservernetworking
        Puppet.err "Could not create server: %s" % $noservernetworking
    else
        class ServerStatus
            attr_reader :ca

            def self.interface
                XMLRPC::Service::Interface.new("status") { |iface|
                    iface.add_method("int status()")
                }
            end

            def initialize(hash = {})
            end

            def status(status = nil, request = nil)
                Puppet.warning "Returning status"
                return 1
            end
        end

        class Server < WEBrick::HTTPServer
            include Puppet::Daemon

            @@handlers = {}
#            # a bit of a hack for now, but eh, wadda ya gonna do?
#            @@handlers = {
#                :Master => Puppet::Server::Master,
#                :CA => Puppet::Server::CA,
#                :Status => Puppet::ServerStatus
#            }

            def self.addhandler(name, handler)
                @@handlers[name] = handler
            end

            Puppet::Server.addhandler(:Status, Puppet::ServerStatus)

            def self.eachhandler
                @@handlers.each { |name, klass|
                    yield(name, klass)
                }
            end
            def self.inithandler(handler,args)
                unless @@handlers.include?(handler)
                    raise ServerError, "Invalid handler %s" % handler
                end

                hclass = @@handlers[handler]

                obj = hclass.new(args)
                return obj
            end

            def initialize(hash = {})
                hash[:Port] ||= Puppet[:masterport]
                hash[:Logger] ||= self.httplog
                hash[:AccessLog] ||= [
                    [ self.httplog, WEBrick::AccessLog::COMMON_LOG_FORMAT ],
                    [ self.httplog, WEBrick::AccessLog::REFERER_LOG_FORMAT ]
                ]

                if hash.include?(:Handlers)
                    unless hash[:Handlers].is_a?(Hash)
                        raise ServerError, "Handlers must have arguments"
                    end

                    @handlers = hash[:Handlers].collect { |handler, args|
                        self.class.inithandler(handler, args)
                    }
                else
                    raise ServerError, "A server must have handlers"
                end

                # okay, i need to retrieve my cert and set it up, somehow
                # the default case will be that i'm also the ca
                if ca = @handlers.find { |handler| handler.is_a?(Puppet::Server::CA) }
                    @driver = ca
                    @secureinit = true
                    self.fqdn
                end

                unless self.readcert
                    unless self.requestcert
                        raise Puppet::Error, "Cannot start without certificates"
                    end
                end

                hash[:SSLCertificate] = @cert
                hash[:SSLPrivateKey] = @key
                hash[:SSLStartImmediately] = true
                hash[:SSLEnable] = true
                hash[:SSLCACertificateFile] = @cacertfile
                hash[:SSLVerifyClient] = OpenSSL::SSL::VERIFY_NONE
                hash[:SSLCertName] = nil

                super(hash)

                # this creates a new servlet for every connection,
                # but all servlets have the same list of handlers
                # thus, the servlets can have their own state -- passing
                # around the requests and such -- but the handlers
                # have a global state

                # mount has to be called after the server is initialized
                self.mount("/RPC2", Puppet::Server::Servlet, @handlers)
            end
        end
    end

    #---------------------------------------------------------------
end

require 'puppet/server/servlet'
require 'puppet/server/master'
require 'puppet/server/ca'
require 'puppet/server/fileserver'
require 'puppet/server/filebucket'