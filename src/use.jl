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
        delete!(env, "PYTHONHOME")
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
    if check
        if cmd[1] == "python"
            exe = _which_python()
        else
            exe = _which(cmd[1])
        end
        if exe === nothing
            error("$(cmd[1]) was not found in the environment")
        end
        # hacky way to make a copy of cmd and change the first entry
        cmd = Base.addenv(cmd)
        cmd.exec[1] = exe
    end
    env = _activate!(copy(ENV))
    Base.setenv(cmd, env)
end

setenv(cmd; kw...) = @lock _global_lock _setenv(cmd; kw...)

function run(cmd::Cmd; kw...)
    Base.run(setenv(cmd; kw...))
end

function _which_python()
    if _config.pycall_compat
        exe = get(ENV, "PYCALL_JL_RUNTIME_PYTHON", "")
        if exe != ""
            return exe
        else
            return _config.pycall_deps[:pyprogramname]::String
        end
    elseif _config.env_mode == :System
        exe = _config.python_path
        if exe != ""
            return exe
        end
        exe = get(ENV, "PYTHON", "")
        if exe != ""
            return exe
        end
    end
    for what in ("python", "python3")
        exe = PythonPkg._which(what)
        if exe !== nothing
            return exe
        end
    end
    return nothing
end

function which_python()
    @lock _global_lock begin
        _init()
        _resolve()
        _which_python()
    end
end

function _which_python_home()
    if _config.pycall_compat
        exe = get(ENV, "PYCALL_JL_RUNTIME_PYTHONHOME", "")
        if exe != ""
            return exe
        else
            return _config.pycall_deps[:PYTHONHOME]::String
        end
    elseif _config.env_mode == :System
        exe = get(ENV, "PYTHONHOME", "")
        if exe != ""
            return exe
        end
    end
end

function which_python_home()
    @lock _global_lock begin
        _init()
        _resolve()
        _which_python_home()
    end
end
