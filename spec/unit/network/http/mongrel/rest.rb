#!/usr/bin/env ruby
#
#  Created by Rick Bradley on 2007-10-16.
#  Copyright (c) 2007. All rights reserved.

require File.dirname(__FILE__) + '/../../../../spec_helper'
require 'puppet/network/http'

describe Puppet::Network::HTTP::MongrelREST, "when initializing" do
    confine "Mongrel is not available" => Puppet.features.mongrel?
    
    before do
        @mock_mongrel = mock('Mongrel server')
        @mock_mongrel.stubs(:register)
        @mock_model = mock('indirected model')
        Puppet::Indirector::Indirection.stubs(:model).with(:foo).returns(@mock_model)
        @params = { :server => @mock_mongrel, :handler => :foo }
    end
    
    it "should require access to a Mongrel server" do
        Proc.new { Puppet::Network::HTTP::MongrelREST.new(@params.delete_if {|k,v| :server == k })}.should raise_error(ArgumentError)
    end
    
    it "should require an indirection name" do
        Proc.new { Puppet::Network::HTTP::MongrelREST.new(@params.delete_if {|k,v| :handler == k })}.should raise_error(ArgumentError)        
    end
    
    it "should look up the indirection model from the indirection name" do
        Puppet::Indirector::Indirection.expects(:model).with(:foo).returns(@mock_model)
        Puppet::Network::HTTP::MongrelREST.new(@params)
    end
    
    it "should fail if the indirection is not known" do
        Puppet::Indirector::Indirection.expects(:model).with(:foo).returns(nil)
        Proc.new { Puppet::Network::HTTP::MongrelREST.new(@params) }.should raise_error(ArgumentError)
    end
    
    it "should register itself with the mongrel server for the singular HTTP methods" do
        @mock_mongrel.expects(:register).with do |*args|
            args.first == '/foo' and args.last.is_a? Puppet::Network::HTTP::MongrelREST
        end
        Puppet::Network::HTTP::MongrelREST.new(@params)
    end

    it "should register itself with the mongrel server for the plural GET method" do
        @mock_mongrel.expects(:register).with do |*args|
            args.first == '/foos' and args.last.is_a? Puppet::Network::HTTP::MongrelREST
        end
        Puppet::Network::HTTP::MongrelREST.new(@params)
    end
end

describe Puppet::Network::HTTP::MongrelREST, "when receiving a request" do
    confine "Mongrel is not available" => Puppet.features.mongrel?
    
    before do
        @mock_request = stub('mongrel http request')
        @mock_head = stub('response head')
        @mock_body = stub('response body', :write => true)
        @mock_response = stub('mongrel http response')
        @mock_response.stubs(:start).yields(@mock_head, @mock_body)
        @mock_model_class = stub('indirected model class')
        @mock_mongrel = stub('mongrel http server', :register => true)
        Puppet::Indirector::Indirection.stubs(:model).with(:foo).returns(@mock_model_class)
        @handler = Puppet::Network::HTTP::MongrelREST.new(:server => @mock_mongrel, :handler => :foo)
    end
    
    def setup_find_request(params = {})
        @mock_request.stubs(:params).returns({  Mongrel::Const::REQUEST_METHOD => 'GET', 
                                                Mongrel::Const::REQUEST_PATH => '/foo/key',
                                                'QUERY_STRING' => ''}.merge(params))
        @mock_model_class.stubs(:find)
    end
    
    def setup_search_request(params = {})
        @mock_request.stubs(:params).returns({  Mongrel::Const::REQUEST_METHOD => 'GET', 
                                                Mongrel::Const::REQUEST_PATH => '/foos',
                                                'QUERY_STRING' => '' }.merge(params))
        @mock_model_class.stubs(:search).returns([])        
    end
    
    def setup_destroy_request(params = {})
        @mock_request.stubs(:params).returns({  Mongrel::Const::REQUEST_METHOD => 'DELETE', 
                                                Mongrel::Const::REQUEST_PATH => '/foo/key',
                                                'QUERY_STRING' => '' }.merge(params))
        @mock_model_class.stubs(:destroy)
    end
    
    def setup_save_request(params = {})
        @mock_request.stubs(:params).returns({  Mongrel::Const::REQUEST_METHOD => 'PUT', 
                                                Mongrel::Const::REQUEST_PATH => '/foo',
                                                'QUERY_STRING' => '' }.merge(params))
        @mock_request.stubs(:body).returns('this is a fake request body')
        @mock_model_instance = stub('indirected model instance', :save => true)
        @mock_model_class.stubs(:new).returns(@mock_model_instance)
    end
    
    def setup_bad_request
        @mock_request.stubs(:params).returns({ Mongrel::Const::REQUEST_METHOD => 'POST', Mongrel::Const::REQUEST_PATH => '/foos'})        
    end

    it "should call the model find method if the request represents a singular HTTP GET" do
        setup_find_request
        @mock_model_class.expects(:find).with('key', {})
        @handler.process(@mock_request, @mock_response)
    end

    it "should call the model search method if the request represents a plural HTTP GET" do
        setup_search_request
        @mock_model_class.expects(:search).with({}).returns([])
        @handler.process(@mock_request, @mock_response)
    end
    
    it "should call the model destroy method if the request represents an HTTP DELETE" do
        setup_destroy_request
        @mock_model_class.expects(:destroy).with('key', {})
        @handler.process(@mock_request, @mock_response)
    end

    it "should call the model save method if the request represents an HTTP PUT" do
        setup_save_request
        @mock_model_instance.expects(:save).with(:data => 'this is a fake request body')
        @handler.process(@mock_request, @mock_response)
    end
    
    it "should fail if the HTTP method isn't supported" do
        @mock_request.stubs(:params).returns({ Mongrel::Const::REQUEST_METHOD => 'POST', Mongrel::Const::REQUEST_PATH => '/foo'})
        @mock_response.expects(:start).with(404)
        @handler.process(@mock_request, @mock_response)
    end
    
    it "should fail if the request's pluralization is wrong" do
        @mock_request.stubs(:params).returns({ Mongrel::Const::REQUEST_METHOD => 'DELETE', Mongrel::Const::REQUEST_PATH => '/foos/key'})
        @mock_response.expects(:start).with(404)
        @handler.process(@mock_request, @mock_response)

        @mock_request.stubs(:params).returns({ Mongrel::Const::REQUEST_METHOD => 'PUT', Mongrel::Const::REQUEST_PATH => '/foos/key'})
        @mock_response.expects(:start).with(404)
        @handler.process(@mock_request, @mock_response)
    end

    it "should fail if the request is for an unknown path" do
        @mock_request.stubs(:params).returns({  Mongrel::Const::REQUEST_METHOD => 'GET', 
                                                Mongrel::Const::REQUEST_PATH => '/bar/key',
                                                'QUERY_STRING' => '' })
        @mock_response.expects(:start).with(404)
        @handler.process(@mock_request, @mock_response)
    end
    
    it "should fail to find model if key is not specified" do
        @mock_request.stubs(:params).returns({ Mongrel::Const::REQUEST_METHOD => 'GET', Mongrel::Const::REQUEST_PATH => '/foo'})
        @mock_response.expects(:start).with(404)
        @handler.process(@mock_request, @mock_response)
    end

    it "should fail to destroy model if key is not specified" do
        @mock_request.stubs(:params).returns({ Mongrel::Const::REQUEST_METHOD => 'DELETE', Mongrel::Const::REQUEST_PATH => '/foo'})
        @mock_response.expects(:start).with(404)
        @handler.process(@mock_request, @mock_response)
    end
    
    it "should fail to save model if data is not specified" do
        @mock_request.stubs(:params).returns({ Mongrel::Const::REQUEST_METHOD => 'PUT', Mongrel::Const::REQUEST_PATH => '/foo'})
        @mock_request.stubs(:body).returns('')
        @mock_response.expects(:start).with(404)
        @handler.process(@mock_request, @mock_response)
    end

    it "should pass HTTP request parameters to model find" do
        setup_find_request('QUERY_STRING' => 'foo=baz&bar=xyzzy')
        @mock_model_class.expects(:find).with do |key, args|
            key == 'key' and args['foo'] == 'baz' and args['bar'] == 'xyzzy'
        end
        @handler.process(@mock_request, @mock_response)
    end
    
    it "should pass HTTP request parameters to model search" do
        setup_search_request('QUERY_STRING' => 'foo=baz&bar=xyzzy')
        @mock_model_class.expects(:search).with do |args|
            args['foo'] == 'baz' and args['bar'] == 'xyzzy'
        end.returns([])
        @handler.process(@mock_request, @mock_response)
    end
    
    it "should pass HTTP request parameters to model delete" do
        setup_destroy_request('QUERY_STRING' => 'foo=baz&bar=xyzzy')
        @mock_model_class.expects(:destroy).with do |key, args|
            key == 'key' and args['foo'] == 'baz' and args['bar'] == 'xyzzy'
        end
        @handler.process(@mock_request, @mock_response)
    end
    
    it "should pass HTTP request parameters to model save" do
        setup_save_request('QUERY_STRING' => 'foo=baz&bar=xyzzy')
        @mock_model_instance.expects(:save).with do |args|
            args[:data] == 'this is a fake request body' and args['foo'] == 'baz' and args['bar'] == 'xyzzy'
        end
        @handler.process(@mock_request, @mock_response)
    end

    it "should generate a 200 response when a model find call succeeds" do
        setup_find_request
        @mock_response.expects(:start).with(200)
        @handler.process(@mock_request, @mock_response)
    end
    
    it "should generate a 200 response when a model search call succeeds" do
        setup_search_request
        @mock_response.expects(:start).with(200)
        @handler.process(@mock_request, @mock_response)
    end
    
    it "should generate a 200 response when a model destroy call succeeds" do
        setup_destroy_request
        @mock_response.expects(:start).with(200)
        @handler.process(@mock_request, @mock_response)
    end

    it "should generate a 200 response when a model save call succeeds" do
        setup_save_request
        @mock_response.expects(:start).with(200)
        @handler.process(@mock_request, @mock_response)
    end
    
    it "should return a serialized object when a model find call succeeds" do
        setup_find_request
        @mock_model_instance = stub('model instance')
        @mock_model_instance.expects(:to_yaml)
        @mock_model_class.stubs(:find).returns(@mock_model_instance)
        @handler.process(@mock_request, @mock_response)                  
    end
    
    it "should return a list of serialized objects when a model search call succeeds" do
        setup_search_request
        mock_matches = [1..5].collect {|i| mock("model instance #{i}", :to_yaml => "model instance #{i}") }
        @mock_model_class.stubs(:search).returns(mock_matches)
        @handler.process(@mock_request, @mock_response)                          
    end
    
    it "should return a serialized success result when a model destroy call succeeds" do
        setup_destroy_request
        @mock_model_class.stubs(:destroy).returns(true)
        @mock_body.expects(:write).with("--- true\n")
        @handler.process(@mock_request, @mock_response)
    end
    
    it "should return a serialized object when a model save call succeeds" do
        setup_save_request
        @mock_model_instance.stubs(:save).returns(@mock_model_instance)
        @mock_model_instance.expects(:to_yaml).returns('foo')
        @handler.process(@mock_request, @mock_response)        
    end
    
    it "should serialize a controller exception when an exception is thrown by find" do
       setup_find_request
       @mock_model_class.expects(:find).raises(ArgumentError) 
       @mock_response.expects(:start).with(404)
       @handler.process(@mock_request, @mock_response)        
    end

    it "should serialize a controller exception when an exception is thrown by search" do
        setup_search_request
        @mock_model_class.expects(:search).raises(ArgumentError) 
        @mock_response.expects(:start).with(404)
        @handler.process(@mock_request, @mock_response)                
    end
    
    it "should serialize a controller exception when an exception is thrown by destroy" do
        setup_destroy_request
        @mock_model_class.expects(:destroy).raises(ArgumentError) 
        @mock_response.expects(:start).with(404)
        @handler.process(@mock_request, @mock_response)                 
    end
    
    it "should serialize a controller exception when an exception is thrown by save" do
        setup_save_request
        @mock_model_instance.expects(:save).raises(ArgumentError) 
        @mock_response.expects(:start).with(404)
        @handler.process(@mock_request, @mock_response)                         
    end
    
    it "should serialize a controller exception if the request fails" do
        setup_bad_request     
        @mock_response.expects(:start).with(404)
        @handler.process(@mock_request, @mock_response)        
    end
end
