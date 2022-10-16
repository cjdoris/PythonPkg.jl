function resolve(; interactive=isinteractive(), kw...)
    @lock _global_lock begin
        _init()
        _resolve(; interactive, kw...)
    end
end

function _resolve(;
    interactive::Bool=false,
    force::Bool=false,
    dry_run::Bool=false,
)
    # assume that if we resolve once, we want to keep resolving
    if !dry_run
        _config.auto_resolve = true
    end
    # if we are forced to re-resolve, then mark as unresolved
    if force
        _config.resolved = false
    end
    # if we have already resolved in this session, then skip
    if _config.resolved
        interactive && @info "PythonPkg: Nothing to do: Already resolved."
        return
    end
    # if we are using the system environment, then skip
    if _config.env_mode == :system
        interactive && @info "PythonPkg: Nothing to do: Using system environment."
        _config.resolved = true
        return
    end
    # if we have python packages to install, we'll need pip
    if !isempty(_python_requirements) && _using_conda()
        _require(_conda_requirements, _PKGID, CondaPackageSpec("pip", version=">=22", channel="conda-forge"))
    end
    # if each requirement is already installed, then skip
    old_meta = _meta_read()
    if old_meta !== nothing
        all_python_specs_resolved = all(
            haskey(old_meta.python_requirements, spec.name) &&
            haskey(old_meta.python_requirements[spec.name], pkg) &&
            old_meta.python_requirements[spec.name][pkg] == spec
            for reqs in values(_python_requirements)
            for (pkg, spec) in reqs
        )
        all_conda_specs_resolved = all(
            haskey(old_meta.conda_requirements, spec.name) &&
            haskey(old_meta.conda_requirements[spec.name], pkg) &&
            old_meta.conda_requirements[spec.name][pkg] == spec
            for reqs in values(_conda_requirements)
            for (pkg, spec) in reqs
        )
    else
        all_python_specs_resolved = false
        all_conda_specs_resolved = false
    end
    if all_python_specs_resolved && all_conda_specs_resolved && !force
        interactive && @info "PythonPkg: Nothing to do: Requirements already installed."
        _config.resolved = true
        return                    
    end
    # if we get this far in a dry run, abort now
    if dry_run
        return
    end
    # gather all the specs to install
    python_specs = [_merge_python_specs(values(reqs)) for reqs in values(_python_requirements) if !isempty(reqs)]
    conda_specs = unique!([spec for reqs in values(_conda_requirements) for spec in values(reqs)])
    conda_channels = unique!([spec for reqs in values(_conda_channel_requirements) for spec in values(reqs)])
    # assume conda-forge if no channels are specified
    if isempty(conda_channels)
        push!(conda_channels, CondaChannelSpec("conda-forge"))
    end
    # remove the meta file before installing anything
    _meta_delete()
    # install the requirements
    @info "PythonPkg: Installing requirements" env=_config.env_path python=python_specs conda=conda_specs conda_channels=conda_channels
    mode = _config.env_mode
    mkpath(_config.env_path)
    # install conda requirements
    if force || !all_conda_specs_resolved
        args = _conda_args(conda_specs, channels=conda_channels)
        push!(args, "-y", "--override-channels", "--no-channel-priority")
        if mode ∈ (:conda_jl, :active_conda)
            if !isempty(conda_specs)
                _conda_run(`install $args`)
            end
        elseif mode ∈ (:project_conda,)
            rm(_config.env_path, force=true, recursive=true)
            _conda_run(`create $args`)
        else
            @assert !_using_conda()
            @warn "PythonPkg has some Conda requirements, but you are not using a Conda environment. These packages will be skipped." conda_specs
        end
    end
    # enable pip if using Conda.jl
    # assume already done if meta exists
    if old_meta === nothing && _config.conda_mode == :conda_jl
        _conda_jl().pip_interop(true, _config.env_path)
    end
    # install python requirements
    if !isempty(python_specs)
        args = _pip_args(python_specs)
        _pip_run(`install $args`)
    end            
    # write out metadata
    _meta_write()
    # all done
    _config.resolved = true
    return
end

function _merge_python_specs(specs)
    # name
    name = first(specs).name
    @assert all(s->s.name == name, specs)
    # versions (concatenate)
    version = join([spec.version for spec in specs if spec != ""], ", ")
    # binary
    binaries = Set(spec.binary for spec in specs if spec.binary != "")
    if length(binaries) == 0
        binary = ""
    elseif length(binaries) == 1
        binary = first(binaries)
    else
        error("The package $name has inconsistent settings: $(join(["binary=$b" for b in binaries], ", "))")
    end
    # done
    PythonPackageSpec(name; version, binary)
end

function _conda_args(specs; channels=CondaChannelSpec[])
    args = String[]
    for spec in specs
        push!(args, _conda_arg(spec))
    end
    for spec in channels
        push!(args, "-c", _conda_arg(spec))
    end
    return args
end

function _pip_args(specs)
    args = String[]
    for spec in specs
        push!(args, _pip_arg(spec))
    end
    for spec in specs
        if spec.binary == "no"
            push!(args, "--no-binary")
        elseif spec.binary == "only"
            push!(args, "--only-binary")
        elseif spec.binary == ""
            # nothing to do
        else
            @assert false
        end
    end
    return args
end

function _conda_run(args)
    if _using_conda()
        mode = _config.conda_mode
        env = _config.env_path
        if mode == :conda_jl
            _conda_jl().runconda(args, env)
        elseif mode == :system
            exe = _config.conda_path
            Base.run(`$exe -p $env $args`)
        elseif mode == :micromamba_jl
            cmd = Base.invokelatest(_micromamba_jl().cmd, `-p $env $args`)::Cmd
            Base.run(cmd)
        else
            error("not implemented")
        end
        return
    else
        error("Not using Conda.")
    end
end

function _pip_run(args)
    env = _config.env_path
    if _using_conda()
        mode = _config.conda_mode
        if mode == :conda_jl
            _conda_jl().pip(args[1], args[2:end], env)
        else
            _activate!() do 
                Base.run(`pip $args`)
            end
        end
    else
        error("not implemented")
    end
end
