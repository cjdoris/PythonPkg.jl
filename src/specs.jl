struct PythonPackageSpec
    name::String
    version::String
    binary::String
    function PythonPackageSpec(name; version="", binary="")
        return new(name, version, binary)
    end
end

function _pip_arg(spec::PythonPackageSpec)
    return spec.version == "" ? spec.name : "$(spec.name) $(spec.version)"
end

struct CondaPackageSpec
    name::String
    version::String
    channel::String
    build::String
    function CondaPackageSpec(name; version="", channel="conda-forge", build="")
        return new(name, version, channel, build)
    end
end

function _conda_arg(spec::CondaPackageSpec)
    args = String[]
    if spec.version != ""
        push!(args, "version='$(spec.version)'")
    end
    if spec.channel != ""
        push!(args, "channel='$(spec.channel)'")
    end
    if spec.build != ""
        push!(args, "build='$(spec.build)'")
    end
    args = join(args, ",")
    return args == "" ? spec.name : "$(spec.name)[$args]"
end

struct CondaChannelSpec
    name::String
end

function _conda_arg(spec::CondaChannelSpec)
    return spec.name
end
