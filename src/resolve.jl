function resolve(;
    interactive::Bool=false,
    force::Bool=false,
    again::Bool=false,
)
    @lock _global_lock begin
        # assume that if we resolve once, we want to keep resolving
        _config.auto_resolve = true
        # if we are forced to re-resolve, then mark as unresolved
        if again || force
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
        # if each requirement is already installed, then skip
        old_meta = _meta_read()
        if !force && old_meta !== nothing
            all_specs_resolved = all(r->_meta_str(r.spec) ∈ old_meta.specs, _requirements)
            all_conda_specs_resolved = all(r->_meta_str(r.spec) ∈ old_meta.conda_specs, _conda_requirements)
            if all_specs_resolved && all_conda_specs_resolved
                interactive && @info "PythonPkg: Nothing to do: Requirements already installed."
                _config.resolved = true
                return                    
            end
        else
            all_specs_resolved = false
            all_conda_specs_resolved = false
        end
        # gather all the specs to install
        specs = _requirement_specs()
        conda_specs = _conda_requirement_specs()
        conda_channels = unique([req.spec for req in _conda_channel_requirements])
        # if we have python packages to install, we'll need pip
        if !isempty(specs) && _using_conda()
            push!(conda_specs, CondaPackageSpec("pip", version=">=22", channel="conda-forge"))
        end
        # assume conda-forge if no channels are specified
        if isempty(conda_channels)
            push!(conda_channels, CondaChannelSpec("conda-forge"))
        end
        # install the requirements
        mode = _config.env_mode
        if mode == :conda_jl
            @info "PythonPkg: Installing requirements into your root Conda.jl environment."
        elseif mode == :active_conda
            @info "PythonPkg: Installing requirements into your active conda environment."
        elseif mode == :project_conda
            @info "PythonPkg: Installing requirements into a project-specific conda environment."
        elseif mode == :active_venv
            @info "PythonPkg: Installing requirements into your virtual environment."
        elseif mode == :project_venv
            @info "PythonPkg: Installing requirements into a project-specific conda environment."
        else
            error("not implemented")
        end
        changed = false
        if !isempty(conda_specs) && (force || !all_conda_specs_resolved)
            changed = true
            if _using_conda()
                args = _conda_args(conda_specs, conda_channels)
                _conda_run(`install $args`)
            else
                @error "PythonPkg has some Conda requirements, but you are not using a Conda environment. These packages will be skipped." conda_specs
            end
        end
        if !isempty(specs) || changed
            args = _pip_args(specs)
            _pip_run(`install $args`)
        end            
        # write out metadata
        _meta_write(; specs, conda_specs)
        # all done
        _config.resolved = true
        return
    end
end

function _requirement_specs()
    # group requirements by name
    grouped_reqs = Dict{String,Vector{PythonReq}}()
    for req in _requirements
        push!(get!(Vector{PythonReq}, grouped_reqs, req.spec.name), req)
    end
    # merge each group into a single spec
    specs = PythonPackageSpec[]
    for (name, reqs) in grouped_reqs
        @assert all(r -> r.spec.name == name, reqs)
        # concatenate versions together
        version = join([req.spec.version for req in reqs if req.spec.version != ""], ", ")
        # select the unique binary setting, or throw
        binaries = Dict{String,Vector{Source}}()
        for req in reqs
            binary = req.spec.binary
            if binary != ""
                push!(get!(Vector{Spec}, binaries, binary), req.source)
            end
        end
        if length(binaries) == 0
            binary = ""
        elseif length(binaries) == 1
            binary = only(keys(binaries))
        else
            error("The package $name has inconsitent settings for binary: $binaries")
        end
        spec = PythonPackageSpec(name; version, binary)
        push!(specs, spec)
    end
    return specs
end

function _conda_requirement_specs()
    # conda is happy with multiple specs for the same package
    # TODO: we should still check for inconsistencies, such as the channel
    return [req.spec for req in _conda_requirements]
end

function _conda_args(specs, channels)
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
        env = _env_path()
        if mode == :conda_jl
            Conda.runconda(args, env)
        elseif mode == :system
            exe = _conda_path()
            run(`$exe $args`)
        else
            error("not implemented")
        end
        return
    else
        error("Not using Conda.")
    end
end

function _pip_run(args)
    if _using_conda()
        activate!() do 
            run(`pip $args`)
        end
    else
        error("not implemented")
    end
end
