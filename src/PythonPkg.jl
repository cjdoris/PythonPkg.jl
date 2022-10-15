module PythonPkg

import Conda, MicroMamba, Scratch

const _global_lock = ReentrantLock()

include("specs.jl")
include("requirements.jl")
include("config.jl")
include("resolve.jl")
include("meta.jl")

# SnoopPrecompile.@precompile_all_calls begin
#     @require("foo")
#     @require("foo", version="")
#     @require("foo", binary="")
#     @require("foo", version="", binary="")
#     __init__()
# end

end
