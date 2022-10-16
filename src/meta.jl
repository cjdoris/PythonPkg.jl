# increment whenever the format of the meta file changes
const _meta_version = 2

function _meta_delete()
    rm(_config.meta_path, force=true)
    return
end

function _meta_write()
    path = _config.meta_path
    try
        open(path, "w") do io
            write(io, _meta_version::Int)
            _meta_write(io, _python_requirements)
            _meta_write(io, _conda_requirements)
            _meta_write(io, _conda_channel_requirements)
            return
        end
    catch
        # don't leave a partially-written file
        rm(path, force=true)
        rethrow()
    end
end

function _meta_read()
    path = _config.meta_path
    isfile(path) || return
    open(path) do io
        version = read(io, Int)
        version == _meta_version || return
        python_requirements = _meta_read(io, Dict{String,Dict{Base.PkgId, PythonPackageSpec}})
        conda_requirements = _meta_read(io, Dict{String,Dict{Base.PkgId, CondaPackageSpec}})
        conda_channel_requirements = _meta_read(io, Dict{String,Dict{Base.PkgId, CondaChannelSpec}})
        (; python_requirements, conda_requirements, conda_channel_requirements)
    end
end

function _meta_write(io::IO, x::Dict)
    write(io, length(x)::Int)
    for (k, v) in x
        _meta_write(io, k)
        _meta_write(io, v)
    end
end

function _meta_read(io::IO, ::Type{Dict{K,V}}) where {K,V}
    x = Dict{K,V}()
    n = read(io, Int)
    for _ in 1:n
        k = _meta_read(io, K)
        v = _meta_read(io, V)
        x[k] = v
    end
    x
end

function _meta_write(io::IO, x::String)
    write(io, sizeof(x)::Int)
    write(io, x)
end

function _meta_read(io::IO, ::Type{String})
    n = read(io, Int)
    b = read(io, n)
    @assert length(b) == n
    String(b)
end

function _meta_write(io::IO, x::Base.PkgId)
    _meta_write(io, x.name)
    if x.uuid === nothing
        write(io, false)
    else
        write(io, true)
        write(io, x.uuid)
    end
end

function _meta_read(io::IO, ::Type{Base.PkgId})
    name = _meta_read(io, String)
    has_uuid = read(io, Bool)
    if has_uuid
        uuid = read(io, Base.UUID)
    else
        uuid = nothing
    end
    Base.PkgId(uuid, name)
end

function _meta_write(io::IO, x::PythonPackageSpec)
    _meta_write(io, x.name)
    _meta_write(io, x.version)
    _meta_write(io, x.binary)
end

function _meta_read(io::IO, ::Type{PythonPackageSpec})
    name = _meta_read(io, String)
    version = _meta_read(io, String)
    binary = _meta_read(io, String)
    PythonPackageSpec(name; version, binary)
end

function _meta_write(io::IO, x::CondaPackageSpec)
    _meta_write(io, x.name)
    _meta_write(io, x.version)
    _meta_write(io, x.channel)
    _meta_write(io, x.build)
end

function _meta_read(io::IO, ::Type{CondaPackageSpec})
    name = _meta_read(io, String)
    version = _meta_read(io, String)
    channel = _meta_read(io, String)
    build = _meta_read(io, String)
    CondaPackageSpec(name; version, channel, build)
end

function _meta_write(io::IO, x::CondaChannelSpec)
    _meta_write(io, x.name)
end

function _meta_read(io::IO, ::Type{CondaChannelSpec})
    name = _meta_read(io, String)
    CondaChannelSpec(name)
end
