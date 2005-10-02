module Puppet
    module ServiceTypes
        module BaseSvc

            # The command used to start.  Generated if the 'binary' argument
            # is passed.
            def startcmd
                if self[:binary]
                    return self[:binary]
                else
                    raise Puppet::Error,
                        "Services must specify a start command or a binary"
                end
            end
        end
    end
end