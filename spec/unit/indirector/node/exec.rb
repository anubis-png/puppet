#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../../spec_helper'

require 'puppet/indirector/node/exec'

describe Puppet::Node::Exec, " when constructing the command to run" do
    before do
        @indirection = mock 'indirection'
        Puppet.settings.stubs(:value).with(:external_nodes).returns("/echo")
        @searcher = Puppet::Node::Exec.new
    end

    it "should use the external_node script as the command" do
        Puppet.expects(:[]).with(:external_nodes).returns("/bin/echo")
        @searcher.command.should == %w{/bin/echo}
    end

    it "should throw an exception if no external node command is set" do
        Puppet.expects(:[]).with(:external_nodes).returns("none")
        proc { @searcher.find("foo") }.should raise_error(ArgumentError)
    end
end

describe Puppet::Node::Exec, " when handling the results of the command" do
    before do
        @indirection = mock 'indirection'
        Puppet.settings.stubs(:value).with(:external_nodes).returns("/echo")
        @searcher = Puppet::Node::Exec.new
        @node = stub 'node', :fact_merge => nil
        @name = "yay"
        Puppet::Node.expects(:new).with(@name).returns(@node)
        @result = {}
        # Use a local variable so the reference is usable in the execute() definition.
        result = @result
        @searcher.meta_def(:execute) do |command|
            return YAML.dump(result)
        end
    end

    it "should translate the YAML into a Node instance" do
        # Use an empty hash
        @searcher.find(@name).should equal(@node)
    end

    it "should set the resulting parameters as the node parameters" do
        @result[:parameters] = {"a" => "b", "c" => "d"}
        @node.expects(:parameters=).with "a" => "b", "c" => "d"
        @searcher.find(@name)
    end

    it "should set the resulting classes as the node classes" do
        @result[:classes] = %w{one two}
        @node.expects(:classes=).with %w{one two}
        @searcher.find(@name)
    end

    it "should merge the node's facts with its parameters" do
        @node.expects(:fact_merge)
        @searcher.find(@name)
    end
end
