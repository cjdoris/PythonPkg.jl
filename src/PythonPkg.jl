module PythonPkg

if isdefined(Base, :Experimental) && isdefined(Base.Experimental, Symbol("@compiler_options"))
    # This brings time-to-first-resolve down from 2000ms to 200ms.
    # Note: compile=min makes --code-coverage not work
    @eval Base.Experimental.@compiler_options optimize=0 infer=false #compile=min
end

const _global_lock = ReentrantLock()

# Standalone utility functions.
include("utils.jl")

# Our equivalents of Pkg.PackageSpec for storing a package plus version bounds etc.
# - PythonPackageSpec
# - CondaPackageSpec
# - CondaChannelSpec
include("specs.jl")

# Functions for modifying the global list of requirements.
# - @require
# - @require_conda
# - @require_conda_channel
# - @require_nothing
include("requirements.jl")

# Functions dealing with the global configuration of the package.
# - init() resets all the state and configures the package from environment variables.
# - using_conda()
include("config.jl")

# Bring everything together and install your requirements.
# - resolve()
include("resolve.jl")

# IO of our julia_pythonpkg_meta file, which stores the state of the most recent resolve in
# an environment. This state is restored by init(), so requirements do not need to be
# re-declared in every session.
include("meta.jl")

# Our equivalent of Pkg.status() to display the status of the requirements.
# - status()
include("status.jl")

# Functions for acivating the environment and using the installed packages.
# - activate!()
# - which()
# - which_python()
# - which_python_home()
# - setenv()
# - run()
include("use.jl")

# Help Julia to precompile the package for faster TTFR (time to first resolve).
include("precompile.jl")

end
