const _meta_version = "1"

function _meta_str(x::PythonPackageSpec)
    return "$(x.name)/$(x.version)/$(x.binary)"
end

function _meta_str(x::CondaPackageSpec)
    return "$(x.name)/$(x.version)/$(x.channel)"
end

function _meta_read()
    path = _meta_path()
    isfile(path) || return
    open(path) do io
        line = readline(io)
        line == "version = $_meta_version" || return
        specs = String[]
        conda_specs = String[]
        for line in eachline(io)
            k, v = split(line, " = ", limit=2)
            if k == "spec"
                push!(specs, v)
            elseif k == "conda_spec"
                push!(conda_specs, v)
            else
                @assert false
            end
        end
        return (; specs, conda_specs)
    end
end

function _meta_write(; specs, conda_specs)
    path = _meta_path()
    open(path, "w") do io
        println(io, "version = ", _meta_version)
        for spec in specs
            println(io, "spec = ", _meta_str(spec))
        end
        for spec in conda_specs
            println(io, "conda_spec = ", _meta_str(spec))
        end
    end
    return
end
