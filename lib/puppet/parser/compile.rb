#  Created by Luke A. Kanies on 2007-08-13.
#  Copyright (c) 2007. All rights reserved.

require 'puppet/external/gratr/digraph'
require 'puppet/external/gratr/import'
require 'puppet/external/gratr/dot'

require 'puppet/node'
require 'puppet/node/configuration'
require 'puppet/util/errors'

# Maintain a graph of scopes, along with a bunch of data
# about the individual configuration we're compiling.
class Puppet::Parser::Compile
    include Puppet::Util
    include Puppet::Util::Errors
    attr_reader :parser, :node, :facts, :collections, :configuration, :node_scope

    # Add a collection to the global list.
    def add_collection(coll)
        @collections << coll
    end

    # Do we use nodes found in the code, vs. the external node sources?
    def ast_nodes?
        parser.nodes.length > 0
    end

    # Store the fact that we've evaluated a class, and store a reference to
    # the scope in which it was evaluated, so that we can look it up later.
    def class_set(name, scope)
        if existing = @class_scopes[name]
            if existing.nodescope? or scope.nodescope?
                raise Puppet::ParseError, "Cannot have classes, nodes, or definitions with the same name"
            else
                raise Puppet::DevError, "Somehow evaluated the same class twice"
            end
        end
        @class_scopes[name] = scope
        @configuration.add_class(name) unless name == ""
    end

    # Return the scope associated with a class.  This is just here so
    # that subclasses can set their parent scopes to be the scope of
    # their parent class, and it's also used when looking up qualified
    # variables.
    def class_scope(klass)
        # They might pass in either the class or class name
        if klass.respond_to?(:classname)
            @class_scopes[klass.classname]
        else
            @class_scopes[klass]
        end
    end

    # Return a list of all of the defined classes.
    def classlist
        return @configuration.classes
    end

    # Compile our configuration.  This mostly revolves around finding and evaluating classes.
    # This is the main entry into our configuration.
    def compile
        # Set the client's parameters into the top scope.
        set_node_parameters()

        evaluate_main()

        evaluate_ast_node()

        evaluate_node_classes()

        evaluate_generators()

        fail_on_unevaluated()

        finish()

        if Puppet[:storeconfigs]
            store()
        end

        return @configuration
    end

    # LAK:FIXME There are no tests for this.
    def delete_collection(coll)
        @collections.delete(coll) if @collections.include?(coll)
    end

    # LAK:FIXME There are no tests for this.
    def delete_resource(resource)
        @resource_table.delete(resource.ref) if @resource_table.include?(resource.ref)
    end

    # Return the node's environment.
    def environment
        unless defined? @environment
            if node.environment and node.environment != ""
                @environment = node.environment
            else
                @environment = nil
            end
        end
        @environment
    end

    # Evaluate all of the classes specified by the node.
    def evaluate_node_classes
        evaluate_classes(@node.classes, topscope)
    end

    # Evaluate each specified class in turn.  If there are any classes we can't
    # find, just tag the configuration and move on.  This method really just
    # creates resource objects that point back to the classes, and then the
    # resources are themselves evaluated later in the process.
    def evaluate_classes(classes, scope, lazy_evaluate = true)
        unless scope.source
            raise Puppet::DevError, "No source for scope passed to evaluate_classes"
        end
        found = []
        classes.each do |name|
            # If we can find the class, then make a resource that will evaluate it.
            if klass = scope.findclass(name)
                # Create a resource to model this class, and then add it to the list
                # of resources.
                resource = Puppet::Parser::Resource.new(:type => "class", :title => klass.classname, :scope => scope, :source => scope.source)
                store_resource(scope, resource)

                # If they've disabled lazy evaluation (which the :include function does),
                # then evaluate our resource immediately.
                resource.evaluate unless lazy_evaluate
                @configuration.tag(klass.classname)
                found << name
            else
                Puppet.info "Could not find class %s for %s" % [name, node.name]
                @configuration.tag(name)
            end
        end
        found
    end

    # Return a resource by either its ref or its type and title.
    def findresource(string, name = nil)
        string = "%s[%s]" % [string.capitalize, name] if name

        @resource_table[string]
    end

    # Set up our compile.  We require a parser
    # and a node object; the parser is so we can look up classes
    # and AST nodes, and the node has all of the client's info,
    # like facts and environment.
    def initialize(node, parser, options = {})
        @node = node
        @parser = parser

        options.each do |param, value|
            begin
                send(param.to_s + "=", value)
            rescue NoMethodError
                raise ArgumentError, "Compile objects do not accept %s" % param
            end
        end

        initvars()
        init_main()
    end

    # Create a new scope, with either a specified parent scope or
    # using the top scope.  Adds an edge between the scope and
    # its parent to the graph.
    def newscope(parent, options = {})
        parent ||= topscope
        options[:compile] = self
        options[:parser] ||= self.parser
        scope = Puppet::Parser::Scope.new(options)
        @scope_graph.add_edge!(parent, scope)
        scope
    end

    # Find the parent of a given scope.  Assumes scopes only ever have
    # one in edge, which will always be true.
    def parent(scope)
        if ary = @scope_graph.adjacent(scope, :direction => :in) and ary.length > 0
            ary[0]
        else
            nil
        end
    end

    # Return any overrides for the given resource.
    def resource_overrides(resource)
        @resource_overrides[resource.ref]
    end

    # Return a list of all resources.
    def resources
        @resource_table.values
    end

    # Store a resource override.
    def store_override(override)
        override.override = true

        # If possible, merge the override in immediately.
        if resource = @resource_table[override.ref]
            resource.merge(override)
        else
            # Otherwise, store the override for later; these
            # get evaluated in Resource#finish.
            @resource_overrides[override.ref] << override
        end
    end

    # Store a resource in our resource table.
    def store_resource(scope, resource)
        # This might throw an exception
        verify_uniqueness(resource)

        # Store it in the global table.
        @resource_table[resource.ref] = resource

        # And in the resource graph.  At some point, this might supercede
        # the global resource table, but the table is a lot faster
        # so it makes sense to maintain for now.
        @configuration.add_edge!(scope.resource, resource)
    end

    # The top scope is usually the top-level scope, but if we're using AST nodes,
    # then it is instead the node's scope.
    def topscope
        node_scope || @topscope
    end

    private

    # If ast nodes are enabled, then see if we can find and evaluate one.
    def evaluate_ast_node
        return unless ast_nodes?

        # Now see if we can find the node.
        astnode = nil
        @node.names.each do |name|
            break if astnode = @parser.nodes[name.to_s.downcase]
        end

        unless (astnode ||= @parser.nodes["default"])
            raise Puppet::ParseError, "Could not find default node or by name with '%s'" % node.names.join(", ")
        end

        # Create a resource to model this node, and then add it to the list
        # of resources.
        resource = Puppet::Parser::Resource.new(:type => "node", :title => astnode.classname, :scope => topscope, :source => topscope.source)
        store_resource(topscope, resource)
        @configuration.tag(astnode.classname)

        resource.evaluate

        # Now set the node scope appropriately, so that :topscope can
        # behave differently.
        @node_scope = class_scope(astnode)
    end

    # Evaluate our collections and return true if anything returned an object.
    # The 'true' is used to continue a loop, so it's important.
    def evaluate_collections
        return false if @collections.empty?

        found_something = false
        exceptwrap do
            # We have to iterate over a dup of the array because
            # collections can delete themselves from the list, which
            # changes its length and causes some collections to get missed.
            @collections.dup.each do |collection|
                found_something = true if collection.evaluate
            end
        end

        return found_something
    end

    # Make sure all of our resources have been evaluated into native resources.
    # We return true if any resources have, so that we know to continue the
    # evaluate_generators loop.
    def evaluate_definitions
        exceptwrap do
            if ary = unevaluated_resources
                ary.each do |resource|
                    resource.evaluate
                end
                # If we evaluated, let the loop know.
                return true
            else
                return false
            end
        end
    end

    # Iterate over collections and resources until we're sure that the whole
    # compile is evaluated.  This is necessary because both collections
    # and defined resources can generate new resources, which themselves could
    # be defined resources.
    def evaluate_generators
        count = 0
        loop do
            done = true

            # Call collections first, then definitions.
            done = false if evaluate_collections
            done = false if evaluate_definitions
            break if done
            if count > 1000
                raise Puppet::ParseError, "Somehow looped more than 1000 times while evaluating host configuration"
            end
        end
    end

    # Find and evaluate our main object, if possible.
    def evaluate_main
        @main = @parser.findclass("", "") || @parser.newclass("")
        @topscope.source = @main
        @main_resource = Puppet::Parser::Resource.new(:type => "class", :title => :main, :scope => @topscope, :source => @main)
        @topscope.resource = @main_resource

        @configuration.add_vertex!(@main_resource)

        @resource_table["Class[main]"] = @main_resource

        @main_resource.evaluate
    end

    # Make sure the entire configuration is evaluated.
    def fail_on_unevaluated
        fail_on_unevaluated_overrides
        fail_on_unevaluated_resource_collections
    end

    # If there are any resource overrides remaining, then we could
    # not find the resource they were supposed to override, so we
    # want to throw an exception.
    def fail_on_unevaluated_overrides
        remaining = []
        @resource_overrides.each do |name, overrides|
            remaining += overrides
        end

        unless remaining.empty?
            fail Puppet::ParseError,
                "Could not find object(s) %s" % remaining.collect { |o|
                    o.ref
                }.join(", ")
        end
    end

    # Make sure we don't have any remaining collections that specifically
    # look for resources, because we want to consider those to be
    # parse errors.
    def fail_on_unevaluated_resource_collections
        remaining = []
        @collections.each do |coll|
            # We're only interested in the 'resource' collections,
            # which result from direct calls of 'realize'.  Anything
            # else is allowed not to return resources.
            # Collect all of them, so we have a useful error.
            if r = coll.resources
                if r.is_a?(Array)
                    remaining += r
                else
                    remaining << r
                end
            end
        end

        unless remaining.empty?
            raise Puppet::ParseError, "Failed to realize virtual resources %s" %
                remaining.join(', ')
        end
    end

    # Make sure all of our resources and such have done any last work
    # necessary.
    def finish
        @resource_table.each { |name, resource| resource.finish if resource.respond_to?(:finish) }
    end

    # Initialize the top-level scope, class, and resource.
    def init_main
        # Create our initial scope and a resource that will evaluate main.
        @topscope = Puppet::Parser::Scope.new(:compile => self, :parser => self.parser)
        @scope_graph.add_vertex!(@topscope)
    end

    # Set up all of our internal variables.
    def initvars
        # The table for storing class singletons.  This will only actually
        # be used by top scopes and node scopes.
        @class_scopes = {}

        # The table for all defined resources.
        @resource_table = {}

        # The list of objects that will available for export.
        @exported_resources = {}

        # The list of overrides.  This is used to cache overrides on objects
        # that don't exist yet.  We store an array of each override.
        @resource_overrides = Hash.new do |overs, ref|
            overs[ref] = []
        end

        # The list of collections that have been created.  This is a global list,
        # but they each refer back to the scope that created them.
        @collections = []

        # A list of tags we've generated; most class names.
        @tags = []

        # A graph for maintaining scope relationships.
        @scope_graph = GRATR::Digraph.new

        # For maintaining the relationship between scopes and their resources.
        @configuration = Puppet::Node::Configuration.new(@node.name)
        @configuration.version = @parser.version
    end

    # Set the node's parameters into the top-scope as variables.
    def set_node_parameters
        node.parameters.each do |param, value|
            @topscope.setvar(param, value)
        end
    end

    # Store the configuration into the database.
    def store
        unless Puppet.features.rails?
            raise Puppet::Error,
                "storeconfigs is enabled but rails is unavailable"
        end

        unless ActiveRecord::Base.connected?
            Puppet::Rails.connect
        end

        # We used to have hooks here for forking and saving, but I don't
        # think it's worth retaining at this point.
        store_to_active_record(@node, @resource_table.values)
    end

    # Do the actual storage.
    def store_to_active_record(node, resources)
        begin
            # We store all of the objects, even the collectable ones
            benchmark(:info, "Stored configuration for #{node.name}") do
                Puppet::Rails::Host.transaction do
                    Puppet::Rails::Host.store(node, resources)
                end
            end
        rescue => detail
            if Puppet[:trace]
                puts detail.backtrace
            end
            Puppet.err "Could not store configs: %s" % detail.to_s
        end
    end

    # Return an array of all of the unevaluated resources.  These will be definitions,
    # which need to get evaluated into native resources.
    def unevaluated_resources
        ary = @resource_table.find_all do |name, object|
            ! object.builtin? and ! object.evaluated?
        end.collect { |name, object| object }

        if ary.empty?
            return nil
        else
            return ary
        end
    end

    # Verify that the given resource isn't defined elsewhere.
    def verify_uniqueness(resource)
        # Short-curcuit the common case, 
        unless existing_resource = @resource_table[resource.ref]
            return true
        end

        if typeclass = Puppet::Type.type(resource.type) and ! typeclass.isomorphic?
            Puppet.info "Allowing duplicate %s" % typeclass.name
            return true
        end

        # Either it's a defined type, which are never
        # isomorphic, or it's a non-isomorphic type, so
        # we should throw an exception.
        msg = "Duplicate definition: %s is already defined" % resource.ref

        if existing_resource.file and existing_resource.line
            msg << " in file %s at line %s" %
                [existing_resource.file, existing_resource.line]
        end

        if resource.line or resource.file
            msg << "; cannot redefine"
        end

        raise Puppet::ParseError.new(msg)
    end
end