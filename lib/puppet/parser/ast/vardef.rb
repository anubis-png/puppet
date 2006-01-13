class Puppet::Parser::AST
    # Define a variable.  Stores the value in the current scope.
    class VarDef < AST::Branch
        attr_accessor :name, :value

        # Look up our name and value, and store them appropriately.  The
        # lexer strips off the syntax stuff like '$'.
        def evaluate(scope)
            name = @name.safeevaluate(scope)
            value = @value.safeevaluate(scope)

            begin
                scope.setvar(name,value)
            rescue Puppet::ParseError => except
                except.line = self.line
                except.file = self.file
                raise except
            rescue => detail
                error = Puppet::ParseError.new(detail)
                error.line = self.line
                error.file = self.file
                error.stack = caller
                raise error
            end
        end

        def each
            [@name,@value].each { |child| yield child }
        end

        def tree(indent = 0)
            return [
                @name.tree(indent + 1),
                ((@@indline * 4 * indent) + self.typewrap(self.pin)),
                @value.tree(indent + 1)
            ].join("\n")
        end

        def to_s
            return "%s => %s" % [@name,@value]
        end
    end

end