#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../spec_helper'

describe Puppet::Parser::Interpreter, " when creating parser instances" do
    before do
        @interp = Puppet::Parser::Interpreter.new
        @parser = mock('parser')
    end

    it "should create a parser with code if there is code defined in the :code setting" do
        Puppet.settings.stubs(:value).with(:code, :myenv).returns("mycode")
        @parser.expects(:string=).with("mycode")
        @parser.expects(:parse)
        Puppet::Parser::Parser.expects(:new).with(:environment => :myenv).returns(@parser)
        @interp.send(:create_parser, :myenv).object_id.should equal(@parser.object_id)
    end

    it "should create a parser with the main manifest when the code setting is an empty string" do
        Puppet.settings.stubs(:value).with(:code, :myenv).returns("")
        Puppet.settings.stubs(:value).with(:manifest, :myenv).returns("/my/file")
        @parser.expects(:parse)
        @parser.expects(:file=).with("/my/file")
        Puppet::Parser::Parser.expects(:new).with(:environment => :myenv).returns(@parser)
        @interp.send(:create_parser, :myenv).should equal(@parser)
    end

    it "should return nothing when new parsers fail" do
        Puppet::Parser::Parser.expects(:new).with(:environment => :myenv).raises(ArgumentError)
        proc { @interp.send(:create_parser, :myenv) }.should raise_error(Puppet::Error)
    end

    it "should create parsers with environment-appropriate manifests" do
        # Set our per-environment values.  We can't just stub :value, because
        # it's called by too much of the rest of the code.
        text = "[env1]\nmanifest = /t/env1.pp\n[env2]\nmanifest = /t/env2.pp"
        file = mock 'file'
        file.stubs(:changed?).returns(true)
        file.stubs(:file).returns("/whatever")
        Puppet.settings.stubs(:read_file).with(file).returns(text)
        Puppet.settings.parse(file)

        parser1 = mock 'parser1'
        Puppet::Parser::Parser.expects(:new).with(:environment => :env1).returns(parser1)
        parser1.expects(:file=).with("/t/env1.pp")
        parser1.expects(:parse)
        @interp.send(:create_parser, :env1)

        parser2 = mock 'parser2'
        Puppet::Parser::Parser.expects(:new).with(:environment => :env2).returns(parser2)
        parser2.expects(:file=).with("/t/env2.pp")
        parser2.expects(:parse)
        @interp.send(:create_parser, :env2)
    end
end

describe Puppet::Parser::Interpreter, " when managing parser instances" do
    before do
        @interp = Puppet::Parser::Interpreter.new
        @parser = mock('parser')
    end

    it "should use the same parser when the parser does not need reparsing" do
        @interp.expects(:create_parser).with(:myenv).returns(@parser)
        @interp.send(:parser, :myenv).should equal(@parser)

        @parser.expects(:reparse?).returns(false)
        @interp.send(:parser, :myenv).should equal(@parser)
    end

    it "should create a new parser when reparse is true" do
        oldparser = mock('oldparser')
        newparser = mock('newparser')
        oldparser.expects(:reparse?).returns(true)
        oldparser.expects(:clear)

        @interp.expects(:create_parser).with(:myenv).returns(oldparser)
        @interp.send(:parser, :myenv).should equal(oldparser)
        @interp.expects(:create_parser).with(:myenv).returns(newparser)
        @interp.send(:parser, :myenv).should equal(newparser)
    end

    it "should fail intelligently if a parser cannot be created and one does not already exist" do
        @interp.expects(:create_parser).with(:myenv).raises(ArgumentError)
        proc { @interp.send(:parser, :myenv) }.should raise_error(ArgumentError)
    end

    it "should keep the old parser if a new parser cannot be created" do
        # Get the first parser in the hash.
        @interp.expects(:create_parser).with(:myenv).returns(@parser)
        @interp.send(:parser, :myenv).should equal(@parser)

        # Have it indicate something has changed
        @parser.expects(:reparse?).returns(true)

        # But fail to create a new parser
        @interp.expects(:create_parser).with(:myenv).raises(ArgumentError)

        # And make sure we still get the old valid parser
        @interp.send(:parser, :myenv).should equal(@parser)
    end

    it "should use different parsers for different environments" do
        # get one for the first env
        @interp.expects(:create_parser).with(:first_env).returns(@parser)
        @interp.send(:parser, :first_env).should equal(@parser)

        other_parser = mock('otherparser')
        @interp.expects(:create_parser).with(:second_env).returns(other_parser)
        @interp.send(:parser, :second_env).should equal(other_parser)
    end
end

describe Puppet::Parser::Interpreter, " when compiling catalog" do
    before do
        @interp = Puppet::Parser::Interpreter.new
        @node = stub 'node', :environment => :myenv
        @compiler = mock 'compile'
        @parser = mock 'parser'
    end

    it "should create a compile with the node and parser" do
        @compiler.expects(:compile).returns(:config)
        @interp.expects(:parser).with(:myenv).returns(@parser)
        Puppet::Parser::Compiler.expects(:new).with(@node, @parser).returns(@compiler)
        @interp.compile(@node)
    end

    it "should fail intelligently when no parser can be found" do
        @node.stubs(:name).returns("whatever")
        @interp.expects(:parser).with(:myenv).returns(nil)
        proc { @interp.compile(@node) }.should raise_error(Puppet::ParseError)
    end
end

describe Puppet::Parser::Interpreter, " when returning catalog version" do
    before do
        @interp = Puppet::Parser::Interpreter.new
    end

    it "should ask the appropriate parser for the catalog version" do
        node = mock 'node'
        node.expects(:environment).returns(:myenv)
        parser = mock 'parser'
        parser.expects(:version).returns(:myvers)
        @interp.expects(:parser).with(:myenv).returns(parser)
        @interp.configuration_version(node).should equal(:myvers)
    end
end
