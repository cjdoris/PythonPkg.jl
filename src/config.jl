mutable struct Config
    # state flags
    inited::Bool
    resolved::Bool
    auto_resolve::Bool
    # modes of operation
    env_mode::Symbol  # none, system, conda_jl, active_conda, active_venv, project_conda, project_venv
    conda_mode::Symbol  # system, conda_jl, micromamba_jl
    python_mode::Symbol # system, python_jll_jl
    pycall_compat::Bool
    # paths of things for creating the env
    env_path::String
    meta_path::String
    conda_path::String
    python_path::String
    # derived information about the env
    pycall_deps::Dict{Symbol,Any}
end

const _config = Config(false, false, false, :none, :none, :none, false, "", "", "", "", Dict{Symbol,Any}())

function Base.show(io::IO, ::MIME"text/plain", c::Config)
    show(io, typeof(c))
    print(io, ":")
    for k in fieldnames(Config)
        println(io)
        print(io, "  ", k, " = ")
        show(io, MIME("text/plain"), getfield(c, k))
    end
end

# function __init__()
#     init()
# end

function _init_pycall_compat(env, conda, python)
    _config.pycall_compat = false
    empty!(_config.pycall_deps)
    # if any env var is set, then we're not in compat mode
    if env != "" || conda != "" || python != ""
        return
    end
    # if PyCall is not in the project, we're not in compat mode
    path = Base.locate_package(_PKGID_PYCALL)
    if path === nothing
        return
    end
    # parse PyCall/deps/deps.jl file
    for line in eachline(joinpath(path, "..", "..", "deps", "deps.jl"))
        ex = Meta.parse(line)
        ex isa Expr || continue
        ex.head == :const || continue
        ex = ex.args[1]
        ex isa Expr || continue
        ex.head == :(=) || continue
        k, v = ex.args
        k isa Symbol || continue
        _config.pycall_deps[k] = v
    end
    _config.pycall_compat = true
end

function init(; kw...)
    @lock _global_lock _init(; kw...)
end

function _init(; force::Bool=false)
    if force
        _config.inited = false
    end
    if _config.inited
        return
    end

    # read the env vars
    env = get(ENV, "JULIA_PYTHONPKG_ENV", "")
    conda = get(ENV, "JULIA_PYTHONPKG_CONDA", "")
    python = get(ENV, "JULIA_PYTHONPKG_PYTHON", "")

    # pycall_compat
    _init_pycall_compat(env, conda, python)

    # default env_mode
    if env == ""
        if conda != ""
            env = "@ProjectConda"
        elseif python != ""
            env = "@ProjectVEnv"
        elseif _config.pycall_compat
            if _config.pycall_deps[:conda]::Bool
                env = "@Conda.jl"
            else
                env = "@System"
            end
        else
            env = "@ProjectConda"
        end
    end

    # env_mode and env_path
    if env == "@Conda.jl"
        _config.env_mode = :conda_jl
        _config.env_path = _conda_jl().ROOTENV::String
    elseif env == "@System"
        _config.env_mode = :system
        _config.env_path = ""
    elseif env == "@ActiveConda"
        _config.env_mode = :active_conda
        _config.env_path = ENV["CONDA_PREFIX"]
    elseif env == "@ActiveVEnv"
        _config.env_mode = :active_venv
        _config.env_path = ENV["VIRTUAL_ENV"]
    elseif env == "@ProjectConda"
        _config.env_mode = :project_conda
        _config.env_path = joinpath(_topmost_project_dir(), ".PythonPkg")
    elseif env == "@ProjectVEnv"
        _config.env_mode = :project_venv
        _config.env_path = joinpath(_topmost_project_dir(), ".PythonPkg")
    else
        error("JULIA_PYTHONPKG_ENV=$env is invalid")
    end

    @assert (_config.env_path != "") ⊻ (_config.env_mode == :system)

    # meta_path
    if _config.env_path == ""
        _config.meta_path == ""
    else
        _config.meta_path = joinpath(_config.env_path, "julia_pythonpkg_meta")
    end

    # default conda_mode
    if conda == ""
        if _config.env_mode == :conda_jl
            conda = "@Conda.jl"
        elseif _config.env_mode == :active_conda
            conda = "@System"
        elseif _config.env_mode == :project_conda
            conda = "@MicroMamba.jl"
        end
    end

    # conda_mode and conda_path
    if conda == "@Conda.jl"
        _config.conda_mode = :conda_jl
        _config.conda_path = ""
    elseif conda == "@MicroMamba.jl"
        _config.conda_mode = :micromamba_jl
        _config.conda_path = ""
    elseif conda == "@System"
        _config.conda_mode = :system
        _config.conda_path = _find_system_conda()
    elseif startswith(conda, "@")
        error("JULIA_PYTHONPKG_CONDA=$conda is invalid")
    elseif conda != ""
        _config.conda_mode = :system
        _config.conda_path = conda
    else
        _config.conda_mode = :none
        _config.conda_path = ""
    end

    @assert (_config.conda_path != "") ⊻ (_config.conda_mode ∈ (:conda_jl, :micromamba_jl, :none))

    # default python_mode
    if python == ""
        if _config.env_mode == :active_venv
            python = "@System"
        elseif _config.env_mode == :project_venv
            python = "@System"
        end
    end

    # python_mode and python_path
    if python == "@System"
        _config.python_mode = :system
        _config.python_path = _find_system_python()
    elseif python == "@Python_jll.jl"
        _config.python_mode = :python_jll_jl
        _config.python_path = ""
    elseif startswith(python, "@")
        error("JULIA_PYTHONPKG_PYTHON=$python is invalid")
    elseif python != ""
        _config.python_mode = :system
        _config.python_path = python
    else
        _config.python_mode = :none
        _config.python_path = ""
    end

    @assert (_config.conda_path != "") ⊻ (_config.conda_mode ∈ (:conda_jl, :micromamba_jl, :none))

    # reset the requirements
    empty!(_python_requirements)
    empty!(_conda_requirements)
    empty!(_conda_channel_requirements)
    meta = _meta_read()
    if meta !== nothing
        copy!(_python_requirements, meta.python_requirements)
        copy!(_conda_requirements, meta.conda_requirements)
        copy!(_conda_channel_requirements, meta.conda_channel_requirements)
    end
    _config.resolved = false

    # done
    _config.inited = true
    return
end

function is_resolved()
    @lock _global_lock begin
        _init()
        _config.resolved
    end
end

function using_conda()
    @lock _global_lock begin
        _init()
        _using_conda()
    end
end

function _using_conda()
    mode = _config.env_mode
    if mode in (:system, :conda_jl, :active_conda, :project_conda)
        return true
    elseif mode in (:active_venv, :project_venv)
        return false
    else
        @assert false
    end
end
