class Puppet::Parser::AST
    # The basic logical structure in Puppet.  Supports a list of
    # tests and statement arrays.
    class CaseStatement < AST::Branch
        attr_accessor :test, :options, :default

        # Short-curcuit evaluation.  Return the value of the statements for
        # the first option that matches.
        def evaluate(scope)
            value = @test.safeevaluate(scope)

            retvalue = nil
            found = false
            
            # Iterate across the options looking for a match.
            @options.each { |option|
                if option.eachvalue { |opval| break true if opval == value }
                    # we found a matching option
                    retvalue = option.safeevaluate(scope)
                    found = true
                    break
                end
            }

            # Unless we found something, look for the default.
            unless found
                if defined? @default
                    retvalue = @default.safeevaluate(scope)
                else
                    Puppet.debug "No true answers and no default"
                end
            end
            return retvalue
        end

        # Do some input validation on our options.
        def initialize(hash)
            values = {}

            super

            # This won't work if we move away from only allowing
            # constants here, but for now, it's fine and useful.
            @options.each { |option|
                unless option.is_a?(CaseOpt)
                    raise Puppet::DevError, "Option is not a CaseOpt"
                end
                if option.default?
                    @default = option
                end
                option.eachvalue { |val|
                    if values.include?(val)
                        raise Puppet::ParseError,
                            "Value %s appears twice in case statement" %
                                val
                    else
                        values[val] = true
                    end
                }
            }
        end

        def tree(indent = 0)
            rettree = [
                @test.tree(indent + 1),
                ((@@indline * indent) + self.typewrap(self.pin)),
                @options.tree(indent + 1)
            ]

            return rettree.flatten.join("\n")
        end

        def each
            [@test,@options].each { |child| yield child }
        end
    end

end