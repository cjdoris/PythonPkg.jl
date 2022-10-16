# These are organised by spec.name => package => spec.
# The package identifies the Julia package which added the spec.
# If the package adds another spec with the same name, it is replaced.
const _python_requirements = Dict{String,Dict{Base.PkgId,PythonPackageSpec}}()
const _conda_requirements = Dict{String,Dict{Base.PkgId,CondaPackageSpec}}()
const _conda_channel_requirements = Dict{String,Dict{Base.PkgId,CondaChannelSpec}}()

function _require(requirements, pkg, spec; delete=false)
    reqs = get!(valtype(requirements), requirements, spec.name)
    if delete
        delete!(reqs, pkg)
        if isempty(reqs)
            delete!(requirements, spec.name)
        end
    else
        reqs[pkg] = spec
    end
    return
end

function _require_nothing(requirements, pkg)
    for (name, reqs) in collect(requirements)
        delete!(reqs, pkg)
        if isempty(reqs)
            delete!(requirements, name)
        end
    end
end

function require(pkg, name; delete=false, kw...)
    pkg = _pkg_id(pkg)
    spec = PythonPackageSpec(name; kw...)
    @lock _global_lock begin
        _init()
        _require(_python_requirements, pkg, spec; delete)
        _config.resolved = false
        _config.auto_resolve && _resolve()
    end
    return
end

function require_conda(pkg, name; delete=false, kw...)
    pkg = _pkg_id(pkg)
    spec = CondaPackageSpec(name; kw...)
    @lock _global_lock begin
        _init()
        _require(_conda_requirements, pkg, spec; delete)
        _config.resolved = false
        _config.auto_resolve && _resolve()
    end
    return
end

function require_conda_channels(pkg, name; delete, kw...)
    pkg = _pkg_id(pkg)
    spec = CondaChannelSpec(name; kw...)
    @lock _global_lock begin
        _init()
        _require(_conda_channel_requirements, pkg, spec; delete)
    end
    return
end

function require_nothing(pkg)
    pkg = _pkg_id(pkg)
    @lock _global_lock begin
        _require_nothing(_python_requirements, pkg)
        _require_nothing(_conda_requirements, pkg)
        _require_nothing(_conda_channel_requirements, pkg)
    end
    return
end

_pkg_id(m::Module) = Base.PkgId(m)
_pkg_id(x::Base.PkgId) = x

function _require_macro(f, inargs, mod)
    pkg = _pkg_id(mod)
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
    ans = :($f($pkg, $(args...); $(params...)))
    return esc(ans)
end

macro require(args...)
    _require_macro(require, args, __module__)
end

macro require_conda(args...)
    _require_macro(require_conda, args, __module__)
end

macro require_conda_channel(args...)
    _require_macro(require_conda_channel, args, __module__)
end

macro require_nothing()
    pkg = _pkg_id(__module__)
    esc(:($require_nothing($pkg)))
end
