module PythonPkg

if isdefined(Base, :Experimental) && isdefined(Base.Experimental, Symbol("@compiler_options"))
    # This brings time-to-first-resolve down from 2000ms to 200ms.
    # Note: compile=min makes --code-coverage not work
    @eval Base.Experimental.@compiler_options optimize=0 infer=false #compile=min
end

const _global_lock = ReentrantLock()

include("utils.jl")
include("specs.jl")
include("requirements.jl")
include("config.jl")
include("resolve.jl")
include("meta.jl")
include("status.jl")

# stuff to precompile
init()
@require("foo")
@require("foo", version="")
@require("foo", binary="")
@require("foo", version="", binary="")
resolve(dry_run=true, interactive=false)
status(io=devnull)
@require_nothing()

end
