mutable struct Config
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

const _config = Config(:none, "", :none, "", :none, "", false, false, false, "")

function __init__()
    empty!(_requirements)
    empty!(_conda_requirements)
    env = get(ENV, "JULIA_PYTHONPKG_ENV", "")
    conda = get(ENV, "JULIA_PYTHONPKG_CONDA", "")
    python = get(ENV, "JULIA_PYTHONPKG_PYTHON", "")
    _config.pycall_compat = true # TODO
    if env == ""
        if conda != ""
            env = "@ProjectConda"
        elseif python != ""
            env = "@ProjectVEnv"
        elseif _config.pycall_compat
            env = "@Conda.jl"
        else
            env = "@ProjectConda"
        end
    end
    if env == "@Conda.jl"
        _config.env_mode = :conda_jl
        if conda == ""
            conda = "@Conda.jl"
        end
    elseif env == "@System"
        _config.env_mode = :system
    elseif env == "@ActiveConda"
        _config.env_mode = :active_conda
        if conda == ""
            conda = "@System"
        end
    elseif env == "@ActiveVEnv"
        _config.env_mode = :active_venv
        if python == ""
            python = "@System"
        end
    elseif env == "@ProjectConda"
        _config.env_mode = :project_conda
        if conda == ""
            conda = "@MicroMamba.jl"
        end
    elseif env == "@ProjectVEnv"
        _config.env_mode = :project_venv
        if python == ""
            python = "@System.jl"
        end
    else
        error("JULIA_PYTHONPKG_ENV=$env is invalid")
    end
    if conda == "@Conda.jl"
        _config.conda_mode = :conda_jl
    elseif conda == "@MicroMamba.jl"
        _config.conda_mode = :micromamba_jl
    elseif conda == "@System"
        _config.conda_mode = :system
    elseif startswith(conda, "@")
        error("JULIA_PYTHONPKG_CONDA=$conda is invalid")
    elseif conda != ""
        _config.conda_mode = :system
        _config.conda_path = conda
    else
        _config.conda_mode = :none
    end
    if python == "@System"
        _config.python_mode = :system
    elseif python == "@Python_jll.jl"
        _config.python_mode = :python_jll_jl
    elseif startswith(python, "@")
        error("JULIA_PYTHONPKG_PYTHON=$python is invalid")
    elseif python != ""
        _config.python_mode = :system
        _config.python_path = python
    else
        _config.python_mode = :none
    end
    _config.resolved = false
end

function is_resolved()
    return @lock _global_lock _config.resolved
end

function _env_path()
    ans = _config.env_path
    if ans == ""
        mode = _config.env_mode
        if mode == :conda_jl
            ans = Conda.ROOTENV::String
        elseif mode == :active_conda
            ans = ENV["CONDA_PREFIX"]
        else
            error("not implemented")
        end
        _config.env_path = ans
    end
    return ans
end

function _meta_path()
    ans = _config.meta_path
    if ans == ""
        ans = joinpath(_env_path(), "julia_pythonpkg_meta")
        _config.meta_path = ans
    end
    return ans
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

function _conda_path()
    ans = _config.conda_path
    if ans == ""
        mode = _config.conda_mode
        if mode == :system
            for what in ("micromamba", "mamba", "conda")
                exe = Sys.which(what)
                if exe !== nothing
                    ans = exe
                    break
                end
            end
            if ans == ""
                error("Cannot find conda, mamba or micromamba. Please ensure it is in your PATH or set JULIA_PYTHONPKG_CONDA.")
            end
        else
            error("not implemented")
        end
        @assert ans != ""
        _config.conda_path = ans
    end
    return ans
end

function _activate!(env::AbstractDict=ENV)
    mode = _config.env_mode
    if mode in (:system, :active_venv, :active_conda)
        # nothing to do
    elseif mode in (:conda_jl, :project_conda)
        root = _env_path()
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
        activate!(env)
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
    resolve()
    return @lock _global_lock _activate!(args...)
end
