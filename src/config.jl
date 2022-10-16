mutable struct Config
    inited::Bool
    env_mode::Symbol  # none, system, conda_jl, active_conda, active_venv, project_conda, project_venv
    env_path::String
    conda_mode::Symbol  # system, conda_jl, micromamba_jl
    conda_path::String
    python_mode::Symbol # system, python_jll_jl
    python_path::String
    resolved::Bool
    auto_resolve::Bool
    pycall_compat::Bool
    meta_path::String
end

const _config = Config(false, :none, "", :none, "", :none, "", false, false, false, "")

# function __init__()
#     init()
# end

function _default_env_conda_python(env, conda, python)
    _config.pycall_compat = false
    env != "" && return (env, conda, python)
    conda != "" && return ("@ProjectConda", conda, python)
    python != "" && return ("@ProjectVEnv", conda, python)
    # compatibility with PyCall - if PyCall is in the project, 
    pycallpath = Base.locate_package(_PKGID_PYCALL)
    pycallpath === nothing && return ("@ProjectConda", conda, python)
    pycallconda = nothing
    pycallpython = nothing
    for line in eachline(joinpath(pycallpath, "..", "..", "deps", "deps.jl"))
        ex = Meta.parse(line)
        ex isa Expr || continue
        ex.head == :const || continue
        ex = ex.args[1]
        ex isa Expr || continue
        ex.head == :(=) || continue
        k, v = ex.args
        if k === :python && v isa String
            pycallpython = v
        elseif k === :conda && v isa Bool
            pycallconda = v
        end
    end
    @assert pycallconda isa Bool
    @assert pycallpython isa String
    @assert !startswith(pycallpython, "@")
    _config.pycall_compat = true
    if pycallconda::Bool
        return ("@Conda.jl", "", "")
    else
        return ("@System", "", pycallpython::String)
    end
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

    # set some defaults
    env, conda, python = _default_env_conda_python(env, conda, python)

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

function _activate!(env::AbstractDict=ENV)
    mode = _config.env_mode
    if mode in (:system, :active_venv, :active_conda)
        # nothing to do
    elseif mode in (:conda_jl, :project_conda)
        root = _config.env_path
        old_path = get(env, "PATH", "")
        path_sep = Sys.iswindows() ? ";" : ":"
        new_path = join(Sys.iswindows() ? ["$root", "$root\\Library\\mingw-w64\\bin", "$root\\Library\\usr\\bin", "$root\\Library\\bin", "$root\\Scripts", "$root\\bin"] : ["$root/bin", "$root/condabin"], path_sep)
        # TODO: if using micromamba, set MAMBA_ROOT_PREFIX and add the executable's directory to PATH
        if old_path !== ""
            new_path = string(new_path, path_sep, old_path)
        end
        env["PATH"] = new_path
        env["CONDA_PREFIX"] = root
        env["CONDA_DEFAULT_ENV"] = root
        env["CONDA_SHLVL"] = "1"
        env["CONDA_PROMPT_MODIFIER"] = "($root) "
    elseif mode in (:project_venv,)
        error("not implemented")
    else
        error("not implemented")
    end
    return env
end

function _activate!(f::Function, env::AbstractDict=ENV)
    mode = _config.env_mode
    if mode in (:system, :active_venv, :active_conda)
        return f()
    else
        old_env = copy(env)
        _activate!(env)
        try
            return f()
        finally
            for k in collect(keys(env))
                if !haskey(old_env, k)
                    delete!(env, k)
                end
            end
            merge!(env, old_env)
        end
    end
end

function activate!(args...)
    @lock _global_lock begin
        _init()
        _resolve()
        _activate!(args...)
    end
end

function _which(prog)
    _init()
    _resolve()
    oldpath = get(ENV, "PATH", nothing)
    delete!(ENV, "PATH")
    try
        _activate!() do 
            return Sys.which(prog)
        end
    finally
        if oldpath === nothing
            delete!(ENV, "PATH")
        else
            ENV["PATH"] = oldpath
        end
    end
end

which(prog) = @lock _global_lock _which(prog)

function _setenv(cmd::Cmd; check::Bool=true)
    if check && _which(cmd[1]) === nothing
        error("$(cmd[1]) was not found in the environment")
    end
    env = _activate!(copy(ENV))
    Base.setenv(cmd, env)
end

setenv(cmd; kw...) = @lock _global_lock _setenv(cmd; kw...)

function run(cmd::Cmd; kw...)
    Base.run(setenv(cmd; kw...))
end
