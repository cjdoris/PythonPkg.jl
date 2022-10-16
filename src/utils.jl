const _PKGID = Base.PkgId(PythonPkg)
const _PKGID_CONDA = Base.PkgId(Base.UUID("8f4d0f93-b110-5947-807f-2305c1781a2d"), "Conda")
const _PKGID_MICROMAMBA = Base.PkgId(Base.UUID("0b3b1443-0f03-428d-bdfb-f27f9c1191ea"), "MicroMamba")
const _PKGID_PYCALL = Base.PkgId(Base.UUID("438e738f-606a-5dbb-bf0a-cddfbfd45ab0"), "PyCall")

function _find_system_conda()
    for what in ("micromamba", "mamba", "conda")
        exe = Sys.which(what)
        if exe !== nothing
            return exe
        end
    end
    error("Cannot find conda, mamba or micromamba. Please ensure it is installed and in your PATH or set JULIA_PYTHONPKG_CONDA to its location.")
end

function _find_system_python()
    for what in ("python3", "python")
        exe = Sys.which(what)
        if exe !== nothing
            return exe
        end
    end
    error("Cannot find python or python3. Please ensure it is installed and in your PATH or set JULIA_PYTHONPKG_PYTHON to its location.")
end

function _project_depends_on(proj, pkgid)
    # TODO: quite hacky, could instead parse the TOML
    name = pkgid.name
    uuid = pkgid.uuid
    if uuid === nothing
        error("pkgid must have uuid")
    end
    ustr = string(uuid)
    if isdir(proj)
        pdir = proj
    elseif isfile(proj)
        pdir = dirname(proj)
    else
        return false
    end
    for file in ("JuliaProject.toml", "Project.toml", "JuliaManifest.toml", "Manifest.toml")
        path = joinpath(pdir, file)
        if isfile(path)
            text = read(path, String)
            if occursin(name, text) && occursin(ustr, text)
                return true
            end
        end
    end
    return false
end

function _topmost_project_dir()
    for proj in Base.load_path()
        if isfile(proj)
            pdir = dirname(proj)
        elseif isdir(proj)
            pdir = proj
        else
            continue
        end
        if _project_depends_on(pdir, _PKGID)
            return pdir
        end
    end
    error("no project in the load_path depends on PythonPkg")
end

_conda_jl() = Base.require(_PKGID_CONDA)

_micromamba_jl() = Base.require(_PKGID_MICROMAMBA)
