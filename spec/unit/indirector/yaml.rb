#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../spec_helper'

require 'puppet/indirector/yaml'

describe Puppet::Indirector::Yaml, " when choosing file location" do
    before :each do
        @indirection = stub 'indirection', :name => :my_yaml, :register_terminus_type => nil
        Puppet::Indirector::Indirection.stubs(:instance).with(:my_yaml).returns(@indirection)
        @store_class = Class.new(Puppet::Indirector::Yaml) do
            def self.to_s
                "MyYaml::MyType"
            end
        end
        @store = @store_class.new

        @subject = Object.new
        @subject.metaclass.send(:attr_accessor, :name)
        @subject.name = :me

        @dir = "/what/ever"
        Puppet.settings.stubs(:use)
        Puppet.settings.stubs(:value).with(:yamldir).returns(@dir)
    end

    describe Puppet::Indirector::Yaml, " when choosing file location" do

        it "should store all files in a single file root set in the Puppet defaults" do
            @store.send(:path, :me).should =~ %r{^#{@dir}}
        end

        it "should use the terminus name for choosing the subdirectory" do
            @store.send(:path, :me).should =~ %r{^#{@dir}/my_yaml}
        end

        it "should use the object's name to determine the file name" do
            @store.send(:path, :me).should =~ %r{me.yaml$}
        end
    end

    describe Puppet::Indirector::Yaml, " when storing objects as YAML" do

        it "should only store objects that respond to :name" do
            proc { @store.save(Object.new) }.should raise_error(ArgumentError)
        end

        it "should convert Ruby objects to YAML and write them to disk" do
            yaml = @subject.to_yaml
            file = mock 'file'
            path = @store.send(:path, @subject.name)
            FileTest.expects(:exist?).with(File.dirname(path)).returns(true)
            File.expects(:open).with(path, "w", 0660).yields(file)
            file.expects(:print).with(yaml)

            @store.save(@subject)
        end

        it "should create the indirection subdirectory if it does not exist" do
            yaml = @subject.to_yaml
            file = mock 'file'
            path = @store.send(:path, @subject.name)
            dir = File.dirname(path)
            FileTest.expects(:exist?).with(dir).returns(false)
            Dir.expects(:mkdir).with(dir)
            File.expects(:open).with(path, "w", 0660).yields(file)
            file.expects(:print).with(yaml)

            @store.save(@subject)
        end
    end

    describe Puppet::Indirector::Yaml, " when retrieving YAML" do

        it "should require the name of the object to retrieve" do
            proc { @store.find(nil) }.should raise_error(ArgumentError)
        end

        it "should read YAML in from disk and convert it to Ruby objects" do
            path = @store.send(:path, @subject.name)

            yaml = @subject.to_yaml
            FileTest.expects(:exist?).with(path).returns(true)
            File.expects(:read).with(path).returns(yaml)

            @store.find(@subject.name).instance_variable_get("@name").should == :me
        end

        it "should fail coherently when the stored YAML is invalid" do
            path = @store.send(:path, @subject.name)

            # Something that will fail in yaml
            yaml = "--- !ruby/object:Hash"

            FileTest.expects(:exist?).with(path).returns(true)
            File.expects(:read).with(path).returns(yaml)

            proc { @store.find(@subject.name) }.should raise_error(Puppet::Error)
        end
    end
end