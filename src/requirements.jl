struct Source
    mod::Module
    file::String
    line::Int
end

struct Requirement{T}
    source::Source
    spec::T
end

const PythonReq = Requirement{PythonPackageSpec}
const CondaReq = Requirement{CondaPackageSpec}
const CondaChannelReq = Requirement{CondaChannelSpec}

const _requirements = PythonReq[]
const _conda_requirements = CondaReq[]
const _conda_channel_requirements = CondaChannelReq[]

function require(source, name; kw...)
    spec = PythonPackageSpec(name; kw...)
    req = Requirement(source, spec)
    @lock _global_lock push!(_requirements, req)
    @lock(_global_lock, _config.auto_resolve) && resolve(; again=true)
    return
end

function require_conda(source, name; kw...)
    spec = CondaPackageSpec(name; kw...)
    req = Requirement(source, spec)
    @lock _global_lock push!(_conda_requirements, req)
    @lock(_global_lock, _config.auto_resolve) && resolve(; again=true)
    return
end

function require_conda_channel(source, name; kw...)
    spec = CondaChannelSpec(name; kw...)
    req = Requirement(source, spec)
    @lock _global_lock push!(_conda_channel_requirements, req)
    return
end

function _require_macro(f, inargs, mod, src)
    source = Source(mod, String(src.file), src.line)
    args = []
    params = []
    for arg in inargs
        if arg isa Expr && arg.head == :parameters
            append!(params, arg.args)
        elseif arg isa Expr && arg.head == :(=)
            push!(params, Expr(:kw, arg.args...))
        else
            push!(args, arg)
        end
    end
    ans = :($f($source, $(args...); $(params...)))
    return esc(ans)
end

macro require(args...)
    _require_macro(require, args, __module__, __source__)
end

macro require_conda(args...)
    _require_macro(require_conda, args, __module__, __source__)
end

macro require_conda_channel(args...)
    _require_macro(require_conda_channel, args, __module__, __source__)
end
