function status(; io::IO=stdout)
    @lock _global_lock begin
        _init()
        _status(; io)
    end
end

function _status(; io::IO=stdout)
    _resolve(; dry_run=true, interactive=false)
    printstyled(io, "PythonPkg", color=:cyan, bold=true)
    printstyled(io, " ", _config.env_path)
    printstyled(io, " (", _config.env_mode, ")", color=:light_black)
    println(io)
    if !_config.resolved
        printstyled(io, "Not resolved. These packages are not available yet.", color=:yellow)
        println(io)
    end
    if _config.pycall_compat
        printstyled(io, "PyCall compatibility mode. Using Conda.jl global environment.", color=:yellow)
        println(io)
    end
    _status_section(io, "Python Packages", _python_requirements)
    _status_section(io, "Conda Packages", _conda_requirements)
    _status_section(io, "Conda Channels", _conda_channel_requirements)
end

function _status_section(io, title, requirements)
    if !isempty(requirements)
        printstyled(io, title, ":", underline=true)
        println(io)
        for name in sort(collect(keys(requirements)))
            for (pkg, spec) in requirements[name]
                print(io, "  ")
                _spec_status(io, spec)
                printstyled(io, " @ ", pkg.name, color=:light_black)
                println(io)
            end
        end
    end
end

function _spec_status(io, spec)
    printstyled(io, spec.name)
    args = _spec_status_args(spec)
    if !isempty(args)
        printstyled(io, " (", join(args, ", "), ")", color=:light_black)
    end
    return
end

function _spec_status_arg!(args, spec, k)
    v = getproperty(spec, k)
    if v != ""
        push!(args, "$k: $v")
    end
    return
end

function _spec_status_args(spec::PythonPackageSpec)
    ans = String[]
    _spec_status_arg!(ans, spec, :version)
    _spec_status_arg!(ans, spec, :binary)
    return ans
end

function _spec_status_args(spec::CondaPackageSpec)
    ans = String[]
    _spec_status_arg!(ans, spec, :version)
    _spec_status_arg!(ans, spec, :channel)
    _spec_status_arg!(ans, spec, :build)
    return ans
end

function _spec_status_args(spec::CondaChannelSpec)
    return String[]
end
